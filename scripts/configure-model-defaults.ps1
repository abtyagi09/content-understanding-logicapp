[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$FoundryAccountName,

    [Parameter(Mandatory)]
    [string]$ModelDefaultsPath
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install it from https://aka.ms/installazurecli.'
}
if (-not (Test-Path -LiteralPath $ModelDefaultsPath -PathType Leaf)) {
    throw "Model defaults file not found: $ModelDefaultsPath"
}

$mapping = Get-Content -LiteralPath $ModelDefaultsPath -Raw | ConvertFrom-Json
if (-not $mapping.modelDeployments -or $mapping.modelDeployments.PSObject.Properties.Count -eq 0) {
    throw "The JSON file must define a non-empty 'modelDeployments' object."
}

& az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Could not select subscription '$SubscriptionId'."
}

$endpoint = & az cognitiveservices account show `
    --name $FoundryAccountName `
    --resource-group $ResourceGroupName `
    --query properties.endpoint `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $endpoint) {
    throw "Could not resolve the endpoint for Foundry account '$FoundryAccountName'."
}
$endpoint = $endpoint.TrimEnd('/')

$token = & az account get-access-token `
    --resource https://cognitiveservices.azure.com/ `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $token) {
    throw 'Could not acquire a Microsoft Entra token for Azure Cognitive Services.'
}
$token = $token.Trim()

$body = $mapping | ConvertTo-Json -Depth 20
$uri = "$endpoint/contentunderstanding/defaults?api-version=2025-11-01"
Invoke-RestMethod -Method Patch `
    -Uri $uri `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType 'application/json' `
    -Body $body | Out-Null

Write-Host "Content Understanding model defaults configured for $FoundryAccountName."
