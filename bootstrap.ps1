param(
    [string]$SubscriptionName = "RRD MSDN Ultimate",
    [string]$AppName = "msal-test"
)


$vaultName = "$($AppName)-kv"
$resourceGroup = "$($AppName)-rg"
$location = "westus2"
$spnName = "$($AppName)-spn"
$spnCert = "$($spnName)-cert"


$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}


Write-Host "1. login to azure [$SubscriptionName]..." -ForegroundColor Green
$azAccount = az account show | ConvertFrom-Json
if ($null -eq $azAccount -or $azAccount.id -ne $SubscriptionId) {
    az login | Out-Null
    az account set -s $SubscriptionName | Out-Null
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
$existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$spnCert']" | ConvertFrom-Json
if ($null -eq $existingCert) {
    $credentialFolder = Join-Path $ScriptFolder "credential"
    New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
    $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
    az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8
    az keyvault certificate create -n $CertName --vault-name $vaultName -p @$defaultPolicyFile | Out-Null
}


[array]$spsFound = az ad sp list --display-name $AppName | ConvertFrom-Json
if ($null -eq $spsFound -or $spsFound.Length -eq 0) {
    Write-Host "Creating service principal with name '$AppName'..."
    $spn = az ad sp create
}