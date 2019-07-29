<#
    the script create a service principal, authenticated with cert, and put cert into key vault
    service principal is granted owner permission to subscription 
#>
param(
    [string]$SubscriptionName = "RRD MSDN Ultimate",
    [string]$AppName = "msal-test"
)

$vaultName = "$($AppName)-kv"
$resourceGroup = "$($AppName)-rg"
$location = "westus2"
$spnName = "$($AppName)-spn"
$spnCert = "$($spnName)-cert"
$containerPort = 5001

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
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

Write-Host "2. Ensure resource group [$resourceGroup]..." -ForegroundColor Green
[array]$rgFound = az group list --query "[?name=='$($resourceGroup)']" | ConvertFrom-Json
if ($null -eq $rgFound -or $rgFound.Length -eq 0) {
    az group create --name $resourceGroup --location $location | Out-Null
}

Write-Host "3. Ensure key vault [$vaultName]..." -ForegroundColor Green
[array]$kvFound = az keyvault list --resource-group $resourceGroup --query "[?name=='$($vaultName)']" | ConvertFrom-Json
if ($null -eq $kvFound -or $kvFound.Length -eq 0) {
    az keyvault create `
        --resource-group $resourceGroup `
        --name $vaultName `
        --sku standard `
        --location $location `
        --enabled-for-deployment $true `
        --enabled-for-disk-encryption $true `
        --enabled-for-template-deployment $true | Out-Null
}

Write-Host "4. Ensure spn cert [$spnCert]..." -ForegroundColor Green
[array]$existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$spnCert']" | ConvertFrom-Json
if ($null -eq $existingCert -or $existingCert.Length -eq 0) {
    $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
    az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8
    $defaultPolicy = Get-Content $defaultPolicyFile | ConvertFrom-Json
    $defaultPolicy.x509CertificateProperties.subject = "CN=$($AppName)"
    $defaultPolicy | ConvertTo-Json -Depth 99 | Out-File $defaultPolicyFile
    az keyvault certificate create -n $spnCert --vault-name $vaultName -p @$defaultPolicyFile | Out-Null
}

Write-Host "5. Ensure spn [$spnName]..." -ForegroundColor Green
[array]$spnFound = az ad sp list --display-name $spnName | ConvertFrom-Json
if ($null -eq $spnFound -or $spnFound.Length -eq 0) {
    az ad sp create-for-rbac -n $spnName --role contributor --keyvault $vaultName --cert $spnCert | Out-Null
    $spnFound = az ad sp list --display-name $spnName | ConvertFrom-Json
}
if ($spnFound.Length -ne 1) {
    throw "duplicated service principal found with name '$spnName'"
}
$spn = $spnFound[0]
$existingAssignments = az role assignment list --assignee $spn.appId --role Owner --scope "/subscriptions/$($azAccount.id)" | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --assignee $spn.appId --role Owner --scope "/subscriptions/$($azAccount.id)" | Out-Null
}

$replyUrl = "http://localhost:$($containerPort)/signin-oidc"
Write-Host "6. Register spn auth redirect url [$replyUrl]..." -ForegroundColor Green

if (-not ($spn.replyUrls -contains $replyUrl)) {
    $replyUrlList = New-Object System.Collections.ArrayList
    $replyUrlList.AddRange([array]$spn.replyUrls)
    $replyUrlList.Add($replyUrl) | Out-Null

    $newReplyUrls = ""
    $replyUrlList | ForEach-Object {
        $newReplyUrls += " " + $_
    }
    az ad app update --id $spn.appId --replyUrls $newReplyUrls
}
else {
    LogInfo -Message "Reply url is already added to service '$($ServiceSetting.service.name)'"
}


$appSettings = @{
    subscriptionId = $azAccount.id
    tenantId       = $azAccount.tenantId
    clientId       = $spn.appId
    clientCertName = $spnCert
    vaultName      = $vaultName
}
$appSettings | ConvertTo-Json -Depth 4