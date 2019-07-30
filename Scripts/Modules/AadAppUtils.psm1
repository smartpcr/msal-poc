function EnsureAadApp() {
    param(
        [Parameter(Mandatory = $true)]
        [object] $AppSettings,

        [Parameter(Mandatory = $true)]
        [object] $GlobalSettings
    )

    $Script:Indent = if ($Script:Indent) { $Script:Indent + 2 } else { 2 }
    $Private:Indentation = "".PadLeft($Script:Indent)
    $Private:Step = 0
    $scriptFolder = Join-Path $global:GitRootFolder "Scripts"
    $credentialFolder = Join-Path $scriptFolder "credential"
    if (-not (Test-Path $credentialFolder)) {
        New-Item $credentialFolder -ItemType Directory -Force | Out-Null
    }
    $appTempFolder = Join-Path $credentialFolder $AppSettings.name
    if (-not (Test-Path $appTempFolder)) {
        New-Item $appTempFolder -ItemType Directory -Force | Out-Null
    }

    Write-Host "$($Private:Indentation)$(++$Private:Step). Ensure aad app [$($AppSettings.name)]..." -ForegroundColor Green
    [array]$appFound = az ad app list --display-name $AppSettings.name | ConvertFrom-Json # native app
    if ($null -eq $appFound -or $appFound.Length -eq 0) {
        if ($AppSettings.type -eq "web") {
            $replyUrl = "http://localhost:$($AppSettings.port)"
            $app = az ad app create --display-name $AppSettings.name --homepage $replyUrl --available-to-other-tenants $true | ConvertFrom-Json
            $serviceIdentifierUri = "api://$($app.appId)"
            az ad app update --id $app.appId --identifier-uris $serviceIdentifierUri
            az ad app update --id $app.appId --set publicClient=$false
        }
        else {
            $replyUrl = "urn:ietf:wg:oauth:2.0:oob"
            $app = az ad app create --display-name $AppSettings.name --native-app --reply-urls $replyUrl | ConvertFrom-Json
        }
    }
    elseif ($appFound.Length -gt 1) {
        throw "multiple apps exists with the same name [$($AppSettings.name)]"
    }
    else {
        $app = $appFound[0]
    }

    Write-Host "$($Private:Indentation)$(++$Private:Step). Ensure owner is added to app" -ForegroundColor Green
    $userPrincipalName = az ad signed-in-user show --query "userPrincipalName"
    $user = az ad user show --upn-or-object-id $userPrincipalName | ConvertFrom-Json
    $userIsAddedAsOwner = $false
    [array]$owners = az ad app owner list --id $app.appId | ConvertFrom-Json
    $owners | ForEach-Object {
        if ($_.objectId -eq $user.objectId) {
            $userIsAddedAsOwner = $true
            Write-Host "Owner [$userPrincipalName] is added to app [$($AppSettings.name)]: $userIsAddedAsOwner"
        }
    }

    if (!$userIsAddedAsOwner) {
        az ad app owner add --id $app.appId --owner-object-id $user.objectId
    }


    Write-Host "$($Private:Indentation)$(++$Private:Step). ensure service principal is created for the app [$($AppSettings.name)]" -ForegroundColor Green
    [array]$spnFound = az ad sp list --display-name $AppSettings.name | ConvertFrom-Json
    if ($null -eq $spnFound -or $spnFound.Length -eq 0) {
        $spn = az ad sp create --id $app.appId | ConvertFrom-Json
    }
    elseif ($spnFound.Length -gt 1) {
        throw "Multiple service principals created with the same name: [$($AppSettings.name)]"
    }
    else {
        $spn = $spnFound[0]
    }
    Write-Host "    service principal: appid=$($spn.appId), objId=$($spn.objectId)"


    Write-Host "$($Private:Indentation)$(++$Private:Step). Ensure app cert [$($AppSettings.appCert)] is created in vault [$($GlobalSettings.vaultName)]"
    $spnCertFile = Join-Path $appTempFolder "$($AppSettings.appCert).pem"
    az keyvault certificate download --vault-name $vaultName --name $spnCert -f $spnCertFile
    [array]$appCredentials = az ad app credential list --id $app.appId --cert | ConvertFrom-Json
    if ($null -eq $appCredentials -or $appCredentials.Length -eq 0) {
        az ad app credential reset --id $app.appId --cert @$spnCertFile
    }
    else {
        $foundSpnCert = $false
        $cert = az keyvault certificate show --vault-name $vaultName --name $spnCert | ConvertFrom-Json
        $appCredentials | ForEach-Object {
            if ($_.customKeyIdentifier -eq $cert.x509ThumbprintHex) {
                $foundSpnCert = $true # TODO: handle expiration
                Write-Host "cert [$($AppSettings.appCert)] is added to app [$($AppSettings.name)]: $foundSpnCert" -ForegroundColor Green
            }
        }

        if (!$foundSpnCert) {
            az ad app credential reset --id $app.appId --cert @$spnCertFile --append
        }
    }

    Write-Host "$($Private:Indentation)$(++$Private:Step). Ensure requested resource access for app [$($AppSettings.name)]" -ForegroundColor Green
    $allResources = Get-Content (Join-Path $scriptFolder "azure_resources.json") | ConvertFrom-Json
    $allPermissions = Get-Content (Join-Path $scriptFolder "permissions.json") | ConvertFrom-Json
    $resourceAccessList = New-Object System.Collections.ArrayList
    if ($null -ne $AppSettings.requestedAccess -and $AppSettings.requestedAccess.Length -gt 0) {
        $AppSettings.requestedAccess | ForEach-Object {
            $resourceName = $_.name
            $resourceId = $allResources[$resourceName]
            $permissions = New-Object System.Collections.ArrayList
            $_.permissions | ForEach-Object {
                $permissionName = $_.name
                $permissionId = $allPermissions[$permissionName]
                $permissions.Add(@{
                        id   = $permissionId
                        type = "Scope"
                    }) | Out-Null
            }
            $resourceAccessList.Add(@{
                    resourceAppId  = $resourceId
                    resourceAccess = $permissions
                }) | Out-Null
        }

        $resourceAccessJsonFile = Join-Path $appTempFolder "resourceAccess.json"
        $resourceAccessList | ConvertTo-Json -Depth 4 | Out-File $resourceAccessJsonFile
        az ad app update --id $app.appId --required-resource-accesses @$resourceAccessJsonFile
    }


    Write-Host "$($Private:Indentation)$(++$Private:Step). Ensure roles for app [$($AppSettings.name)]" -ForegroundColor Green
    if ($null -ne $AppSettings.roles -and $AppSettings.roles.Length -gt 0) {
        $appRoleList = New-Object System.Collections.ArrayList
        $AppSettings.roles | ForEach-Object {
            $appRoleList.Add(@{
                    allowedMemberTypes = $_.types
                    description        = $_.description
                    displayName        = $_.name
                    value              = $_.value
                    isEnabled          = $true
                }) | Out-Null
        }
        $appRolesJsonFile = Join-Path $appTempFolder "appRoles.json"
        $appRoleList | ConvertTo-Json -Depth 4 | Out-File $appRolesJsonFile
        az ad app update --id $app.appId --app-roles @$appRolesJsonFile
    }
}