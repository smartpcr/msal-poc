<#
    the script will:
    1) create an aad app for each app in manifest (apps_manifest.yaml)
    2) create service principal for each app
    3) create requested resource access for each app
    4) create app roles for each app

#>

param(
    [string]$AppManifestFile = "samples_manifest.yaml"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$global:GitRootFolder = $gitRootFolder
$script:Indent = 2
$scriptFolder = Join-Path $gitRootFolder "Scripts"
$modulesFolder = Join-Path $scriptFolder "Modules"
$examplesFolder = Join-Path $global:GitRootFolder "examples"
if (-not (Test-Path $AppManifestFile)) {
    $AppManifestFile = Join-Path $examplesFolder $AppManifestFile
}
if (-not (Test-Path $AppManifestFile)) {
    throw "Unable to find manifest file [$AppManifestFile]"
}

Import-Module (Join-Path $modulesFolder "Common.psm1") -Force
Import-Module (Join-Path $modulesFolder "AadAppUtils.psm1") -Force
Import-Module (Join-Path $modulesFolder "YamlUtils.psm1") -Force

Initialize

UsingScope ("Login to azure") {
    $appsSettings = Get-Content $AppManifestFile -Raw | ConvertFrom-Yaml2 -Ordered
    $globalSettings = $appsSettings.global
    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ine $globalSettings.subscriptionName) {
        az login | Out-Null
        az account set --subscription $globalSettings.subscriptionName | Out-Null
        $azAccount = az account show | ConvertFrom-Json
    }
}

UsingScope("Ensure resource group") {
    [array]$rgFound = az group list --query "[?name=='$($globalSettings.resourceGroup)']" | ConvertFrom-Json
    if ($null -eq $rgFound -or $rgFound.Length -eq 0) {
        az group create --name $globalSettings.resourceGroup --location $globalSettings.location | Out-Null
    }
}

UsingScope ("Ensure key vault [$($globalSettings.vaultName)]") {
    [array]$kvFound = az keyvault list --resource-group $globalSettings.resourceGroup --query "[?name=='$($globalSettings.vaultName)']" | ConvertFrom-Json
    if ($null -eq $kvFound -or $kvFound.Length -eq 0) {
        az keyvault create `
            --resource-group $globalSettings.resourceGroup `
            --name $globalSettings.vaultName `
            --sku standard `
            --location $globalSettings.location `
            --enabled-for-deployment $true `
            --enabled-for-disk-encryption $true `
            --enabled-for-template-deployment $true | Out-Null
    }
}

$appsSettings.apps | ForEach-Object {
    $appSettings = $_
    UsingScope("Ensure app [$($appSettings.name)]") {
        EnsureAadApp -AppSettings $appSettings -GlobalSettings $globalSettings
    }
}

<#
$vaultName = "$($AppName)-kv"
$resourceGroup = "$($AppName)-rg"
$location = "westus2"
$spnName = "$($AppName)-spn"
$spnCert = "$($spnName)-cert"
$clientAppName = "$($AppName)-Client"
$replyUrl = "http://localhost:5001"
# https://blogs.msdn.microsoft.com/aaddevsup/2018/06/06/guid-table-for-windows-azure-active-directory-permissions/
$permissions = @{
    UserProfile_Read   = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"
    Directory_Read     = "5778995a-e1bf-45b8-affa-663a9f3f4d04"
    Directory_Write    = "78c8a3c8-a07e-4b9e-af1b-b5ccab50a175"
    User_Impersonation = "a42657d6-7f20-40e3-b6f0-cee03008a62a"
}

# https://www.shawntabrizi.com/aad/common-microsoft-resources-azure-active-directory/
$azureResources = @{
    "AAD_Graph_API"                = "00000002-0000-0000-c000-000000000000"
    "O365_Exchange_Online"         = "00000002-0000-0ff1-ce00-000000000000"
    "Microsoft_Graph"              = "00000003-0000-0000-c000-000000000000"
    "Skype_Business_Online"        = "00000004-0000-0ff1-ce00-000000000000"
    "O365_Yammer"                  = "00000005-0000-0ff1-ce00-000000000000"
    "OneNote"                      = "2d4d3d8e-2be3-4bef-9f87-7875a61c29de"
    "Azure_Service_Management_API" = "797f4846-ba00-4fd7-ba43-dac1f8f63013"
    "O365_Management_API"          = "c5393580-f805-4401-95e8-94b7a6ef2fc2"
    "Teams_Services"               = "cc15fd57-2c6c-4117-a88c-83b1d56b4bbe"
    "Azure_Key_Vault"              = "cfa8b339-82a2-471a-a3c9-0fc0be7a4093"
}

if (-not (Test-Path $scriptFolder)) {
    New-Item $scriptFolder -ItemType Directory -Force | Out-Null
}
$credentialFolder = Join-Path $ScriptFolder "credential"
if (-not (Test-Path $credentialFolder)) {
    New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
}

Write-Host "1. login to azure [$SubscriptionName]..." -ForegroundColor Green
$azAccount = az account show | ConvertFrom-Json
if ($null -eq $azAccount -or $azAccount.id -ne $SubscriptionId) {
    az login | Out-Null
    az account set -s $SubscriptionName | Out-Null
    $azAccount = az account show | ConvertFrom-Json
}


Write-Host "4. Ensure aad app [$AppName]..." -ForegroundColor Green
[array]$appFound = az ad app list --display-name $AppName | ConvertFrom-Json # native app
if ($null -eq $appFound -or $appFound.Length -eq 0) {
    $app = az ad app create --display-name $AppName --homepage $replyUrl --available-to-other-tenants $true | ConvertFrom-Json

}
elseif ($appFound.Length -gt 1) {
    throw "multiple apps exists with the same name '$AppName'"
}
else {
    $app = $appFound[0]
}

$serviceIdentifierUri = "api://$($app.appId)"
az ad app update --id $app.appId --identifier-uris $serviceIdentifierUri
az ad app update --id $app.appId --set publicClient=$false
az ad app update --id $app.appId --available-to-other-tenants $true
az ad app update --id $app.appId --homepage $replyUrl

Write-Host "5. Ensure user is addes as owner to aad app" -ForegroundColor Green
[array]$spnFound = az ad sp list --display-name $AppName | ConvertFrom-Json
if ($null -eq $spnFound -or $spnFound.Length -eq 0) {
    $spn = az ad sp create --id $app.appId | ConvertFrom-Json
}
elseif ($spnFound.Length -gt 1) {
    throw "Multiple service principals created with the same name: '$AppName'"
}
else {
    $spn = $spnFound[0]
}

$userPrincipalName = az ad signed-in-user show --query "userPrincipalName"
$user = az ad user show --upn-or-object-id $userPrincipalName | ConvertFrom-Json
$userIsAddedAsOwner = $false
[array]$owners = az ad app owner list --id $app.appId | ConvertFrom-Json
$owners | ForEach-Object {
    if ($_.objectId -eq $user.objectId) {
        $userIsAddedAsOwner = $true
    }
}
if (!$userIsAddedAsOwner) {
    az ad app owner add --id $app.appId --owner-object-id $user.objectId
}



Write-Host "6. Ensure aad app [$clientAppName]" -ForegroundColor Green
[array]$clientAppFound = az ad app list --display-name $clientAppName | ConvertFrom-Json # native app
if ($null -eq $clientAppFound -or $clientAppFound.Length -eq 0) {
    $clientApp = az ad app create --display-name $clientAppName --native-app --reply-urls "urn:ietf:wg:oauth:2.0:oob" --available-to-other-tenants $true | ConvertFrom-Json

}
elseif ($clientAppFound.Length -gt 1) {
    throw "multiple apps exists with the same name '$clientAppName'"
}
else {
    $clientApp = $clientAppFound[0]
}
az ad app update --id $clientApp.appId --set publicClient=$false


Write-Host "7. Ensure client service principal [$clientAppName]" -ForegroundColor Green
[array]$clientSpnFound = az ad sp list --display-name $clientAppName | ConvertFrom-Json
if ($null -eq $clientSpnFound -or $clientSpnFound.Length -eq 0) {
    $clientSpn = az ad sp create --id $clientApp.appId | ConvertFrom-Json
}
elseif ($clientSpnFound.Length -gt 1) {
    throw "Multiple service principals created with the same name: '$clientAppName'"
}
else {
    $clientSpn = $clientSpnFound[0]
}


Write-Host "8. Ensure user is added as owner to client app [$clientAppName]" -ForegroundColor Green
$userIsOwnerToClientApp = $false
[array]$clientOwners = az ad app owner list --id $clientApp.appId | ConvertFrom-Json
$clientOwners | ForEach-Object {
    if ($_.objectId -eq $user.objectId) {
        $userIsOwnerToClientApp = $true
    }
}
if (!$userIsOwnerToClientApp) {
    az ad app owner add --id $clientApp.appId --owner-object-id $user.objectId
}


Write-Host "9. Create html file for service app and client app" -ForegroundColor Green
$htmlFile = "createdApps.html"
Set-Content -Value "<html><body><table>" -Path $htmlFile
Add-Content -Value "<thead><tr><th>Application</th><th>AppId</th><th>Url in the Azure portal</th></tr></thead><tbody>" -Path $htmlFile
$servicePortalUrl = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/CallAnAPI/appId/" + $app.AppId + "/objectId/" + $spn.ObjectId + "/isMSAApp/"
Add-Content -Value "<tr><td>service</td><td>$($app.appId)</td><td><a href='$servicePortalUrl'>TodoListService (active-directory-dotnet-native-aspnetcore-v2)</a></td></tr>" -Path $htmlFile
$clientPortalUrl = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/CallAnAPI/appId/" + $clientApp.appId + "/objectId/" + $clientSpn.objectId + "/isMSAApp/"
Add-Content -Value "<tr><td>client</td><td>$($clientApp.appId)</td><td><a href='$clientPortalUrl'>TodoListClient (active-directory-dotnet-native-aspnetcore-v2)</a></td></tr>" -Path $htmlFile


Write-Host "10. Ensure permission 'user_impersonation' is granted to service app [$AppName]"
$resourceAccessJson =
@"
[
    {
        "resourceAppId": "$($azureResources.Microsoft_Graph)",
        "resourceAccess": [
            {
                "id": "$($permissions.User_Impersonation)",
                "type": "Scope"
            }
        ]
    }
]
"@
$resourceAccessJsonFile = "resourceAccess.json"
$resourceAccessJson | Out-File $resourceAccessJsonFile
az ad app update --id $app.appId --required-resource-accesses @$resourceAccessJsonFile

az ad app update --id $app.appId --set groupMembershipClaims=All

$appRolesJson = @"
[
    {
        "allowedMemberTypes": ["User", "Application"],
        "description": "Approvers can mark task as approved",
        "displayName": "Approver",
        "isEnabled": "true",
        "value": "approver"
    }
]
"@
$appRolesJsonFile = "appRoles.json"
$appRolesJson | Out-File $appRolesJsonFile
az ad app update --id $app.appId --app-roles @$appRolesJsonFile


Write-Host "11. Ensure spn cert [$spnCert]..." -ForegroundColor Green
[array]$existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$spnCert']" | ConvertFrom-Json
if ($null -eq $existingCert -or $existingCert.Length -eq 0) {
    $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
    az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8
    $defaultPolicy = Get-Content $defaultPolicyFile | ConvertFrom-Json
    $defaultPolicy.x509CertificateProperties.subject = "CN=$($AppName)"
    $defaultPolicy | ConvertTo-Json -Depth 99 | Out-File $defaultPolicyFile
    az keyvault certificate create -n $spnCert --vault-name $vaultName -p @$defaultPolicyFile | Out-Null
}

Write-Host "12. Ensure spn [$spnName] uses cert [$spnCert]..." -ForegroundColor Green
$spnCertFile = "$($spnCert).pem"
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
        }
    }

    if (!$foundSpnCert) {
        az ad app credential reset --id $app.appId --cert @$spnCertFile --append
    }
}


Write-Host "13. Ensure service principal have right role assignment" -ForegroundColor Green
$existingAssignments = az role assignment list --assignee $spn.appId --role Owner --scope "/subscriptions/$($azAccount.id)" | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --assignee $spn.appId --role Owner --scope "/subscriptions/$($azAccount.id)" | Out-Null
}


Write-Host "14. Register spn auth redirect url [$replyUrl]..." -ForegroundColor Green
if (-not ($app.replyUrls -contains $replyUrl)) {
    $replyUrlList = New-Object System.Collections.ArrayList
    $replyUrlList.AddRange([array]$spn.replyUrls)
    $replyUrlList.Add($replyUrl) | Out-Null

    $newReplyUrls = ""
    $replyUrlList | ForEach-Object {
        $newReplyUrls += " " + $_
    }
    az ad app update --id $app.appId --replyUrls $newReplyUrls # TODO: fix this
}
else {
    LogInfo -Message "Reply url is already added to service '$($ServiceSetting.service.name)'"
}


$serviceAppSettings = @{
    subscriptionId = $azAccount.id
    tenantId       = $azAccount.tenantId
    clientId       = $spn.appId
    clientCertName = $spnCert
    vaultName      = $vaultName
}
$serviceAppSettings | ConvertTo-Json -Depth 4

$clientAppSettings = @{
    subscriptionId = $azAccount.id
    tenantId       = $azAccount.tenantId
    clientId       = $clientApp.appId
    vaultName      = $vaultName
}
$clientAppSettings | ConvertTo-Json -Depth 4
#>