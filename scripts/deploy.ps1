[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$Location,

    [ValidatePattern('^[a-z0-9]{3,7}$')]
    [string]$NamePrefix = 'cuapp',

    [ValidateSet('WS1', 'WS2', 'WS3')]
    [string]$LogicAppSku = 'WS1',

    [string]$ContentUnderstandingAnalyzer = 'prebuilt-invoice',

    [switch]$DeployFoundry,

    [string]$VnetAddressPrefix = '10.50.0.0/16',

    [string]$InfraSubnetPrefix = '10.50.1.0/26',

    [string]$JumpboxSubnetPrefix = '10.50.2.0/24',

    [string]$PrivateEndpointSubnetPrefix = '10.50.3.0/24',

    [string]$SshPublicKeyPath,

    [switch]$DeployJumpbox,

    [switch]$ApproveAzureFilesSharedKeyException,

    [switch]$WhatIfOnly,

    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install it from https://aka.ms/installazurecli.'
}

$cliVersionJson = & az version --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the Azure CLI version.'
}
$cliVersion = [version](($cliVersionJson | ConvertFrom-Json).'azure-cli')
if ($cliVersion -lt [version]'2.48.1') {
    throw 'Azure CLI 2.48.1 or later is required for Entra-authenticated ZIP deployment.'
}

$null = & az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not signed in. Run az login, then rerun this script.'
}

Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId)
$selectedSubscription = (& az account show --query id --output tsv).Trim()
if ($LASTEXITCODE -ne 0 -or $selectedSubscription -ne $SubscriptionId) {
    throw "Could not select subscription '$SubscriptionId'."
}

$sshPublicKey = ''
if ($DeployJumpbox) {
    if (-not $SshPublicKeyPath) {
        throw 'DeployJumpbox requires -SshPublicKeyPath pointing to an SSH public-key file (.pub).'
    }
    if (-not (Test-Path -LiteralPath $SshPublicKeyPath -PathType Leaf)) {
        throw "SSH public-key file not found: $SshPublicKeyPath"
    }

    $sshPublicKey = (Get-Content -LiteralPath $SshPublicKeyPath -Raw).Trim()
    if ($sshPublicKey -notmatch '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp\d+)\s+\S+') {
        throw 'The SSH key file does not look like a supported public key. Never pass a private key.'
    }
}

$templatePath = Join-Path $projectRoot 'bicep\main.bicep'
$compiledTemplatePath = Join-Path ([System.IO.Path]::GetTempPath()) "$([guid]::NewGuid().ToString('N')).json"
try {
    Invoke-Az -Arguments @('bicep', 'build', '--file', $templatePath, '--outfile', $compiledTemplatePath)
}
finally {
    Remove-Item -LiteralPath $compiledTemplatePath -Force -ErrorAction SilentlyContinue
}

$providers = @(
    'Microsoft.Authorization',
    'Microsoft.Network',
    'Microsoft.Storage',
    'Microsoft.Web',
    'Microsoft.KeyVault'
)
if ($DeployJumpbox) {
    $providers += 'Microsoft.Compute'
}
if ($DeployFoundry) {
    $providers += 'Microsoft.CognitiveServices'
}
foreach ($provider in $providers) {
    $registrationState = (& az provider show --namespace $provider --query registrationState --output tsv).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read registration state for '$provider'."
    }
    if ($registrationState -ne 'Registered') {
        Invoke-Az -Arguments @('provider', 'register', '--namespace', $provider, '--wait')
    }
}

$resourceGroupExists = (& az group exists --name $ResourceGroupName).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Could not check resource group '$ResourceGroupName'."
}
if ($resourceGroupExists -ne 'true') {
    Invoke-Az -Arguments @(
        'group', 'create',
        '--name', $ResourceGroupName,
        '--location', $Location,
        '--output', 'none'
    )
}

$deploymentName = 'cu-' + (Get-Date -Format 'yyyyMMddHHmmss')
$parameters = @(
    "namePrefix=$NamePrefix",
    "location=$Location",
    "logicAppSku=$LogicAppSku",
    "contentUnderstandingAnalyzer=$ContentUnderstandingAnalyzer",
    "deployFoundry=$($DeployFoundry.IsPresent.ToString().ToLowerInvariant())",
    "vnetAddressPrefix=$VnetAddressPrefix",
    "infraSubnetPrefix=$InfraSubnetPrefix",
    "jumpboxSubnetPrefix=$JumpboxSubnetPrefix",
    "privateEndpointSubnetPrefix=$PrivateEndpointSubnetPrefix",
    "deployJumpbox=$($DeployJumpbox.IsPresent.ToString().ToLowerInvariant())",
    "azureFilesSharedKeyExceptionApproved=$($ApproveAzureFilesSharedKeyException.IsPresent.ToString().ToLowerInvariant())"
)
if ($DeployJumpbox) {
    $parameters += "adminSshPublicKey=$sshPublicKey"
}

$deploymentArguments = @(
    'deployment', 'group', 'what-if',
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templatePath,
    '--parameters'
) + $parameters
Invoke-Az -Arguments $deploymentArguments

if ($WhatIfOnly) {
    return
}

if (-not $Approve) {
    $confirmation = Read-Host "Deploy infrastructure and workflows to $SubscriptionId / $ResourceGroupName? Type YES to continue"
    if ($confirmation -cne 'YES') {
        throw 'Deployment cancelled.'
    }
}

$createArguments = @(
    'deployment', 'group', 'create',
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--mode', 'Incremental',
    '--template-file', $templatePath,
    '--parameters'
) + $parameters + @('--output', 'json')

$deploymentOutput = & az @createArguments
if ($LASTEXITCODE -ne 0) {
    throw "Infrastructure deployment '$deploymentName' failed."
}
$outputs = ($deploymentOutput -join "`n" | ConvertFrom-Json).properties.outputs
$logicAppName = [string]$outputs.logicAppName.value
$logicAppUrl = [string]$outputs.logicAppUrl.value
if (-not $logicAppName) {
    throw "Deployment '$deploymentName' completed without a Logic App name output."
}

Start-Sleep -Seconds 60
$logicAppPath = Join-Path $projectRoot 'logicapp'
$packagePath = Join-Path ([System.IO.Path]::GetTempPath()) "$logicAppName-$([guid]::NewGuid().ToString('N')).zip"
$stagingPath = Join-Path ([System.IO.Path]::GetTempPath()) "$logicAppName-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $logicAppPath -Recurse -File | Where-Object Name -ne 'local.settings.json') {
        $relativePath = $file.FullName.Substring($logicAppPath.Length).TrimStart('\')
        $stagedFile = Join-Path $stagingPath $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $stagedFile) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $stagedFile -Force
    }
    Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $packagePath -Force
    Invoke-Az -Arguments @(
        'webapp', 'deploy',
        '--resource-group', $ResourceGroupName,
        '--name', $logicAppName,
        '--src-path', $packagePath,
        '--type', 'zip',
        '--async', 'false'
    )
}
finally {
    Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
}

$httpClient = [System.Net.Http.HttpClient]::new()
$hostReady = $false
$lastStatusCode = 'no response'
try {
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            $response = $httpClient.GetAsync($logicAppUrl).GetAwaiter().GetResult()
            $lastStatusCode = [int]$response.StatusCode
            $response.Dispose()
            if ($lastStatusCode -ne 503) {
                $hostReady = $true
                break
            }
        }
        catch [System.Net.Http.HttpRequestException] {
            $lastStatusCode = $_.Exception.Message
        }
        catch [System.Threading.Tasks.TaskCanceledException] {
            $lastStatusCode = 'request timed out'
        }

        Start-Sleep -Seconds 15
    }
}
finally {
    $httpClient.Dispose()
}
if (-not $hostReady) {
    throw "The Logic App endpoint did not become healthy (last response: $lastStatusCode). Check WEBSITE_CONTENTAZUREFILECONNECTIONSTRING, WEBSITE_CONTENTSHARE, private DNS, TCP 445 reachability, and the Storage policy exception."
}

Write-Host ''
Write-Host "Logic App: $logicAppName"
Write-Host "Endpoint:  $logicAppUrl"
Write-Host "Storage:   $($outputs.storageAccountName.value)"
if ($outputs.foundryAccountName.value) {
    Write-Host "Foundry:   $($outputs.foundryAccountName.value)"
}
else {
    Write-Host 'Foundry:   not deployed (DeployFoundry was not specified)'
}
Write-Host ''
Write-Warning 'Before processing documents, deploy the model(s) required by the analyzer and configure Content Understanding model defaults.'
Write-Warning 'Upload test documents to the private documents container from a network path that can reach the Storage private endpoint.'
Write-Host 'Deployment outputs do not include the Azure Files connection string or Storage account keys.'
