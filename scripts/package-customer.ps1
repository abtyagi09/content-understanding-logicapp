[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot 'customer-deployment.zip'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$stagingPath = Join-Path ([System.IO.Path]::GetTempPath()) "cu-customer-$([guid]::NewGuid().ToString('N'))"
$packagePath = Join-Path ([System.IO.Path]::GetTempPath()) "cu-customer-$([guid]::NewGuid().ToString('N')).zip"

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI with Bicep is required to generate the customer templates.'
}

$sshPublicKey = $env:JUMPBOX_SSH_PUBLIC_KEY
try {
    Remove-Item Env:JUMPBOX_SSH_PUBLIC_KEY -ErrorAction SilentlyContinue
    Invoke-Az -Arguments @(
        'bicep', 'build',
        '--file', (Join-Path $projectRoot 'bicep\main.bicep'),
        '--outfile', (Join-Path $projectRoot 'azuredeploy.json')
    )
    Invoke-Az -Arguments @(
        'bicep', 'build-params',
        '--file', (Join-Path $projectRoot 'bicep\main.bicepparam'),
        '--outfile', (Join-Path $projectRoot 'azuredeploy.parameters.json')
    )

    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    foreach ($fileName in @(
        'README.md',
        '.gitignore',
        'azuredeploy.json',
        'azuredeploy.parameters.json',
        'foundry-model-defaults.example.json',
        'architecture.excalidraw'
    )) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $fileName) -Destination $stagingPath
    }

    foreach ($directoryName in @('.github', 'bicep', 'scripts')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $directoryName) -Destination $stagingPath -Recurse
    }

    $logicAppSource = Join-Path $projectRoot 'logicapp'
    $logicAppDestination = Join-Path $stagingPath 'logicapp'
    New-Item -ItemType Directory -Path $logicAppDestination | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $logicAppSource -Recurse -File | Where-Object Name -ne 'local.settings.json') {
        $relativePath = $file.FullName.Substring($logicAppSource.Length).TrimStart([char]'\')
        $stagedFile = Join-Path $logicAppDestination $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $stagedFile) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $stagedFile -Force
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $packagePath -Force
    Move-Item -LiteralPath $packagePath -Destination $OutputPath -Force
}
finally {
    if ($null -ne $sshPublicKey) {
        $env:JUMPBOX_SSH_PUBLIC_KEY = $sshPublicKey
    }
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
}

Write-Host "Customer deployment package created: $OutputPath"
