# Content Understanding Logic App Deployment (Terraform)

Reusable Azure public-cloud deployment for a private Azure Logic Apps Standard
document-processing solution with optional **Azure Content Understanding in Foundry Tools**,
deployed via Terraform (Azure Verified Modules).

The Logic App polls a configured Outlook mailbox for invoice-like attachments,
uploads matching files to a private Storage container, analyzes them with the
Content Understanding analyzer, and writes the structured result to a second
private Storage container. See `spoke-architecture-new.png` (or the editable
`spoke-architecture.excalidraw` source) for the network layout and the full
request/data flow, including exactly how each hop authenticates.

## What this deploys

- One VNet (default `10.50.0.0/16`) with three subnets: Logic App integration,
  private endpoints, and an optional jump box
- A private StorageV2 account with `documents` and `results` containers, plus
  an Azure Files share for the Logic App's runtime content
- A Windows Logic App Standard site (system-assigned + user-assigned managed
  identity), optionally with a private inbound endpoint
- Optionally, a private Azure AI Foundry account and Content Understanding
  project, with the completion (`gpt-5.2` by default) and embedding
  (`text-embedding-3-large` by default) model deployments it requires
- Optionally, Microsoft Graph `Mail.ReadWrite` granted to the Logic App's
  identities so it can poll and mark messages in the configured mailbox
- Optionally, a private Ubuntu jump box for operators without another path
  into the VNet

No model defaults are patched on the Content Understanding resource via the
preview `PATCH /contentunderstanding/defaults` API (it depends on a
region-specific preview feature flag that isn't reliably available at deploy
time). Instead, the workflow passes `modelDeployments` inline on every analyze
request, pointing at the Terraform-managed model deployments.

## Prerequisites

- Azure subscription/region with Logic Apps Standard, Private Endpoints, and
  (if enabling Foundry) Content Understanding availability and quota
- Terraform >= 1.11.0 and Azure CLI >= 2.48.1, or a GitHub Actions runner with
  OIDC federation configured (see below)
- The deploying identity needs Contributor and Role Based Access Control
  Administrator (or equivalent) on the target resource group
- If `grant_outlook_graph_permissions = true`: the deploying identity must
  also hold Microsoft Graph application permissions
  `Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All`
  (admin-consented), since Terraform creates the Graph role assignment via
  the `azuread` provider

## Deploy locally

```powershell
az login
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit values for your environment
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

After `apply`, package and publish the Logic App workflow:

```powershell
$logicAppName = terraform output -raw logic_app_name
$resourceGroup = "<your resource group>"
Compress-Archive -Path ..\logicapp\* -DestinationPath ..\logicapp.zip -Force
az webapp deploy --resource-group $resourceGroup --name $logicAppName --src-path ..\logicapp.zip --type zip
```

## Deploy via GitHub Actions

Run `.github/workflows/deploy-terraform.yml` (workflow_dispatch). It
provisions infrastructure, then automatically packages and publishes the Logic
App workflow and polls the host until healthy -- no manual package/publish
step required.

Configure a Microsoft Entra application or user-assigned identity with a
federated credential matching the repository and branch. Grant it the Azure
permissions described in Prerequisites above, plus (if
`grantOutlookGraphPermissions` will be used) the Graph application
permissions noted above.

Set repository variables:
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- `AZURE_TFSTATE_RESOURCE_GROUP`, `AZURE_TFSTATE_STORAGE_ACCOUNT` (lowercase
  letters/numbers, 3-24 chars), `AZURE_TFSTATE_CONTAINER`

Key workflow inputs:
- `deployFoundry` (default `false`): creates the Foundry account, project,
  private endpoint, DNS zones, and both model deployments
- `outlookMailboxUser`: mailbox UPN/email for the Logic App to poll
- `grantOutlookGraphPermissions` (default `false`): grants Graph
  `Mail.ReadWrite` to the Logic App's identities -- requires the admin
  consent described in Prerequisites
- `logicAppPublicNetworkAccess` (default `false`): set `true` to let the
  hosted GitHub runner publish and health-check the Logic App package. If
  `false`, publish and verify from a VNet-connected runner or machine instead.

## After deployment

If `deploy_foundry = true`, the completion and embedding model deployments
and Graph permission grant (when enabled) are already in place -- no further
manual configuration is required for the Logic App to start processing mail.

If `deploy_foundry = false`, no Content Understanding endpoint is configured
and the workflow's analyze step will fail; set `deploy_foundry = true` and
re-apply once you're ready to process documents.

Confirm the workflow is healthy:

```powershell
az rest --method get --uri "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<logicAppName>/hostruntime/runtime/webhooks/workflow/api/management/workflows?api-version=2018-11-01"
```

Send a test email with a PDF attachment to the configured mailbox; within one
polling interval (2 minutes by default) the workflow should upload it to the
`documents` container, analyze it, and write the result JSON to the `results`
container.

## Known limitations

- This package ships only the verified, end-to-end `ProcessOutlookInvoiceRecreated`
  workflow (poll inbox -> upload -> analyze -> store), which handles the full
  flow in a single workflow. A separate blob-trigger workflow
  (`ProcessDocument`) exists in the source repository but is not included
  here because it does not currently start successfully (an AzureBlob
  built-in connector configuration issue). Ask your delivery contact if you
  need blob-trigger-based processing independent of the Outlook mailbox flow.
- The private jump box has no public IP and no implicit Internet egress; use
  an existing private connectivity path or separately provision Bastion.
- These templates target Azure public cloud; Foundry and Key Vault DNS
  suffixes are not parameterized for sovereign clouds.
