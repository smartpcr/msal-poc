function EnsureAadApp() {
    param(
        [Parameter(Mandatory = $true)]
        [object] $AppSettings,

        [Parameter(Mandatory = $true)]
        [object] $GlobalSettings
    )

    $scriptFolder = Join-Path $global:GitRootFolder "Scripts"
    $credentialFolder = Join-Path $scriptFolder "credential"
    if (-not (Test-Path $credentialFolder)) {
        New-Item $credentialFolder -ItemType Directory -Force | Out-Null
    }
    $appTempFolder = Join-Path $credentialFolder $AppSettings.name
    if (-not (Test-Path $appTempFolder)) {
        New-Item $appTempFolder -ItemType Directory -Force | Out-Null
    }

    LogStep -Message "Ensure aad app [$($AppSettings.name)]..."
    [array]$appFound = az ad app list --display-name $AppSettings.name | ConvertFrom-Json
    if ($null -eq $appFound -or $appFound.Length -eq 0) {
        if ($AppSettings.type -eq "web") {
            $replyUrl = "http://localhost:$($AppSettings.port)"
            $app = az ad app create --display-name $AppSettings.name --homepage $replyUrl --available-to-other-tenants $true | ConvertFrom-Json
            $serviceIdentifierUri = "api://$($app.appId)"
            az ad app update --id $app.appId --identifier-uris $serviceIdentifierUri
            az ad app update --id $app.appId --set publicClient=$false
        }
        else {  # native app
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
    $Global:Apps = if ($Global:Apps) { $Global:Apps } else { New-Object Hashtable }
    if (($Global:Apps).ContainsKey($AppSettings.name)) {
        ($Global:Apps)[$AppSettings.name] = $app.appId
    }
    else {
        ($Global:Apps).Add($AppSettings.name, $app.appId) | Out-Null
    }

    LogStep -Message "Ensure owner is added to app"
    $userPrincipalName = az ad signed-in-user show --query "userPrincipalName"
    $user = az ad user show --upn-or-object-id $userPrincipalName | ConvertFrom-Json
    $userIsAddedAsOwner = $false
    [array]$owners = az ad app owner list --id $app.appId | ConvertFrom-Json
    $owners | ForEach-Object {
        if ($_.objectId -eq $user.objectId) {
            $userIsAddedAsOwner = $true
            LogStep "Owner [$userPrincipalName] is added to app [$($AppSettings.name)]: $userIsAddedAsOwner"
        }
    }

    if (!$userIsAddedAsOwner) {
        az ad app owner add --id $app.appId --owner-object-id $user.objectId
    }


    LogStep -Message "ensure service principal is created for the app [$($AppSettings.name)]"
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
    LogStep "service principal: appid=$($spn.appId), objId=$($spn.objectId)"


    LogStep -Message "Ensure app cert [$($AppSettings.appCert)] is created in vault [$($GlobalSettings.vaultName)]"
    [array]$existingCerts = az keyvault certificate list --vault-name $GlobalSettings.vaultName --query "[?name=='$($AppSettings.appCert)']" | ConvertFrom-Json
    if ($null -eq $existingCerts -or $existingCerts.Length -eq 0) {
        $defaultPolicyFile = Join-Path $appTempFolder "default_policy.json"
        az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8 -Force | Out-Null
        $defaultPolicy = Get-Content $defaultPolicyFile | ConvertFrom-Json
        $defaultPolicy.x509CertificateProperties.subject = "CN=$($AppSettings.name)"
        $defaultPolicy | ConvertTo-Json -Depth 99 | Out-File $defaultPolicyFile
        az keyvault certificate create --name $appSettings.appCert --vault-name $GlobalSettings.vaultName -p @$defaultPolicyFile | Out-Null
    }
    $spnCertFile = Join-Path $appTempFolder "$($AppSettings.appCert).pem"
    if (Test-Path $spnCertFile) {
        Remove-Item $spnCertFile -Force | Out-Null
    }

    [array]$appCredentials = az ad app credential list --id $app.appId --cert | ConvertFrom-Json
    if ($null -eq $appCredentials -or $appCredentials.Length -eq 0) {
        az keyvault certificate download --vault-name $GlobalSettings.vaultName --name $AppSettings.appCert -f $spnCertFile
        az ad app credential reset --id $app.appId --cert @$spnCertFile | Out-Null
    }
    else {
        $foundSpnCert = $false
        $cert = az keyvault certificate show --vault-name $GlobalSettings.vaultName --name $AppSettings.appCert | ConvertFrom-Json
        $appCredentials | ForEach-Object {
            if ($_.customKeyIdentifier -eq $cert.x509ThumbprintHex) {
                $foundSpnCert = $true # TODO: handle expiration
                LogStep -Message "cert [$($AppSettings.appCert)] is added to app [$($AppSettings.name)]: $foundSpnCert"
            }
        }

        if (!$foundSpnCert) {
            az keyvault certificate download --vault-name $GlobalSettings.vaultName --name $AppSettings.appCert -f $spnCertFile
            az ad app credential reset --id $app.appId --cert @$spnCertFile --append | Out-Null
        }
    }

    LogStep -Message "Ensure requested resource access for app [$($AppSettings.name)]"
    $allResources = Get-Content (Join-Path $scriptFolder "resources.json") | ConvertFrom-Json | ConvertTo-Yaml2 | ConvertFrom-Yaml2 -Ordered
    $allPermissions = Get-Content (Join-Path $scriptFolder "permissions.json") | ConvertFrom-Json | ConvertTo-Yaml2 | ConvertFrom-Yaml2 -Ordered
    $resourceAccessList = New-Object System.Collections.ArrayList
    if ($null -ne $AppSettings.requestedAccess -and $AppSettings.requestedAccess.Count -gt 0) {
        [array]$AppSettings.requestedAccess | ForEach-Object {
            $resourceName = $_.name
            $resourceId = $allResources[$resourceName]
            $permissions = New-Object System.Collections.ArrayList
            if ($null -eq $resourceId) {
                $resourceId = ($Global:Apps)[$resourceName]
                $dependentApp = az ad app show --id $resourceId | ConvertFrom-Json
                $_.permissions | ForEach-Object {
                    $permissionName = $_.name
                    $appRoleFound = $dependentApp.appRoles | Where-Object { $_.value -eq $permissionName }
                    if ($null -ne $appRoleFound) {
                        $permissions.Add(@{
                            id   = $appRoleFound.id
                            type = "Role"
                        }) | Out-Null
                    }
                }
            }
            else {
                $_.permissions | ForEach-Object {
                    $permissionName = $_.name
                    $permissionId = $allPermissions[$permissionName]
                    if ($null -ne $permissionId) {
                        $permissions.Add(@{
                            id   = $permissionId
                            type = "Scope"
                        }) | Out-Null
                    }
                }
            }
            if ($null -ne $resourceId -and $permissions.Count -gt 0) {
                $resourceAccessList.Add(@{
                    resourceAppId  = $resourceId
                    resourceAccess = $permissions
                }) | Out-Null
            }
        }

        $resourceAccessJsonFile = Join-Path $appTempFolder "resourceAccess.json"
        $resourceAccessList | ConvertTo-Json -Depth 4 | Out-File $resourceAccessJsonFile
        az ad app update --id $app.appId --required-resource-accesses @$resourceAccessJsonFile
    }


    LogStep -Message "Ensure roles for app [$($AppSettings.name)]"
    if ($null -ne $AppSettings.roles -and $AppSettings.roles.Length -gt 0) {
        $appRoleList = New-Object System.Collections.ArrayList
        $AppSettings.roles | ForEach-Object {
            $appRoleList.Add(@{
                    allowedMemberTypes = $_.types
                    description        = $_.description
                    displayName        = $_.name
                    value              = $_.name
                    isEnabled          = $true
                }) | Out-Null
        }
        $appRolesJsonFile = Join-Path $appTempFolder "appRoles.json"
        $appRoleList | ConvertTo-Json -Depth 4 | Out-File $appRolesJsonFile
        az ad app update --id $app.appId --app-roles @$appRolesJsonFile
    }
}