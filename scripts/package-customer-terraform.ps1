[CmdletBinding()]
param(
    [string]$OutputPath,

    # Ship the ProcessDocument blob-trigger workflow. It currently fails to start
    # ("connectionString missing" from the AzureBlob built-in connector) and is
    # excluded by default so customers don't receive a broken workflow silently.
    [switch]$IncludeProcessDocumentWorkflow,

    # Ship the simpler ProcessOutlookInvoice workflow (uploads attachments to the
    # documents container but does not call Content Understanding). Excluded by
    # default because ProcessOutlookInvoiceRecreated is the verified, end-to-end
    # workflow (poll -> upload -> analyze -> store) customers should use.
    [switch]$IncludeBasicOutlookWorkflow
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot 'terraform-customer-deployment.zip'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$stagingPath = Join-Path ([System.IO.Path]::GetTempPath()) "cu-tf-customer-$([guid]::NewGuid().ToString('N'))"
$packagePath = Join-Path ([System.IO.Path]::GetTempPath()) "cu-tf-customer-$([guid]::NewGuid().ToString('N')).zip"

try {
    New-Item -ItemType Directory -Path $stagingPath | Out-Null

    # --- Top-level files ---
    foreach ($fileName in @(
        '.gitignore',
        'foundry-model-defaults.example.json',
        'spoke-architecture-new.png',
        'spoke-architecture.excalidraw'
    )) {
        $source = Join-Path $projectRoot $fileName
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $stagingPath
        }
    }

    # --- Terraform-focused README (trimmed; no Bicep/ARM instructions) ---
    $readmePath = Join-Path $PSScriptRoot 'templates\CUSTOMER-README-TERRAFORM.md'
    if (Test-Path -LiteralPath $readmePath) {
        Copy-Item -LiteralPath $readmePath -Destination (Join-Path $stagingPath 'README.md')
    }
    else {
        Write-Warning "Terraform customer README template not found at $readmePath; package will not include a README."
    }

    # --- .github workflows: only the Terraform deployment workflow ---
    $workflowsDestination = Join-Path $stagingPath '.github\workflows'
    New-Item -ItemType Directory -Path $workflowsDestination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot '.github\workflows\deploy-terraform.yml') -Destination $workflowsDestination

    # --- terraform/ directory: source files only, never state/plan/cache artifacts ---
    $terraformSource = Join-Path $projectRoot 'terraform'
    $terraformDestination = Join-Path $stagingPath 'terraform'
    New-Item -ItemType Directory -Path $terraformDestination | Out-Null
    $terraformExcludeNames = @(
        'terraform.portal-rg.tfvars.example',
        'terraform.portal-rg.rebuild.tfvars'
    )
    Get-ChildItem -LiteralPath $terraformSource -Filter '*.tf' -File | Copy-Item -Destination $terraformDestination
    Copy-Item -LiteralPath (Join-Path $terraformSource '.terraform.lock.hcl') -Destination $terraformDestination
    foreach ($name in @(
        'terraform.tfvars.example',
        'terraform.tfvars.phase1-private-infra.example',
        'terraform.tfvars.phase2-content-understanding.example'
    )) {
        $source = Join-Path $terraformSource $name
        if ((Test-Path -LiteralPath $source) -and ($terraformExcludeNames -notcontains $name)) {
            Copy-Item -LiteralPath $source -Destination $terraformDestination
        }
    }

    # --- logicapp/: host.json, connections.json, and the verified workflow(s) ---
    $logicAppSource = Join-Path $projectRoot 'logicapp'
    $logicAppDestination = Join-Path $stagingPath 'logicapp'
    New-Item -ItemType Directory -Path $logicAppDestination | Out-Null
    Copy-Item -LiteralPath (Join-Path $logicAppSource 'host.json') -Destination $logicAppDestination
    Copy-Item -LiteralPath (Join-Path $logicAppSource 'connections.json') -Destination $logicAppDestination

    Copy-Item -LiteralPath (Join-Path $logicAppSource 'ProcessOutlookInvoiceRecreated') -Destination $logicAppDestination -Recurse
    Get-ChildItem -LiteralPath (Join-Path $logicAppDestination 'ProcessOutlookInvoiceRecreated') -Filter 'local.settings.json' -Recurse |
        Remove-Item -Force

    if ($IncludeBasicOutlookWorkflow) {
        Copy-Item -LiteralPath (Join-Path $logicAppSource 'ProcessOutlookInvoice') -Destination $logicAppDestination -Recurse
        Get-ChildItem -LiteralPath (Join-Path $logicAppDestination 'ProcessOutlookInvoice') -Filter 'local.settings.json' -Recurse |
            Remove-Item -Force
    }

    if ($IncludeProcessDocumentWorkflow) {
        Write-Warning 'Including ProcessDocument workflow: it currently fails to start (AzureBlob connector "connectionString missing"). Fix before shipping, or remove after import if the customer does not need blob-trigger processing.'
        Copy-Item -LiteralPath (Join-Path $logicAppSource 'ProcessDocument') -Destination $logicAppDestination -Recurse
        Get-ChildItem -LiteralPath (Join-Path $logicAppDestination 'ProcessDocument') -Filter 'local.settings.json' -Recurse |
            Remove-Item -Force
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $packagePath -Force
    Move-Item -LiteralPath $packagePath -Destination $OutputPath -Force
}
finally {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
}

Write-Host "Terraform customer deployment package created: $OutputPath"
Write-Host 'Included workflow(s): ProcessOutlookInvoiceRecreated (verified end-to-end: poll -> upload -> analyze -> store)'
if (-not $IncludeBasicOutlookWorkflow) {
    Write-Host 'Excluded: ProcessOutlookInvoice (upload-only variant, superseded by ProcessOutlookInvoiceRecreated). Pass -IncludeBasicOutlookWorkflow to include it.'
}
if (-not $IncludeProcessDocumentWorkflow) {
    Write-Host 'Excluded: ProcessDocument (blob-trigger workflow; currently broken -- AzureBlob connector "connectionString missing"). Pass -IncludeProcessDocumentWorkflow to include it anyway.'
}
