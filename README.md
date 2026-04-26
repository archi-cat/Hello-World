# Hello World — Azure Two-Tier Application

A two-tier Python web application deployed on Azure using infrastructure-as-code and fully automated CI/CD pipelines. Built as a learning project covering Azure App Service, Azure SQL Database, Application Gateway, Managed Identity, Application Insights, and Terraform.

---

## Architecture

```
User (internet)
│
▼
App Gateway (Standard V2) ← public HTTPS entry point
│
▼
Web App (Azure App Service) ← Flask, renders DB status
│  HTTPS
▼
API (Azure App Service) ← Flask, checks SQL connectivity
│  Managed Identity (no password)
▼
Azure SQL Database (Basic, 5 DTUs)
```

Both App Services sit inside a VNet with dedicated subnets. Each has its own Application Insights instance feeding into a shared Log Analytics workspace. A metric alert fires when DTU consumption exceeds 85% for 20 minutes.

---

## Repository structure

```
hello-world/
├── app/
│   ├── web/                        # Flask web app
│   │   ├── app.py                  # Calls API, renders DB status page
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── api/                        # Flask API
│       ├── app.py                  # Checks SQL DB connection via Managed Identity
│       ├── requirements.txt
│       └── Dockerfile              # Includes Microsoft ODBC Driver 18
├── terraform/
│   ├── main.tf                     # All Azure resources
│   ├── variables.tf                # Input variable declarations
│   ├── outputs.tf                  # App URL, SQL FQDN, identity IDs
│   ├── backend.tf                  # Azure Blob Storage remote state
│   └── providers.tf                # Providers used to deploy the infrastructure
├── scripts/
│   └── Set-SqlManagedIdentity.ps1  # Grants API Managed Identity DB access
└── .github/
└── workflows/
├── infra.yml               # Terraform plan + apply
└── deploy.yml              # Docker build, push, deploy + SQL setup
```

---

## Prerequisites

The following tools must be installed locally:

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9.0
- [Git](https://git-scm.com/)
- PowerShell 7+ (for the SQL setup script)

You will also need:

- An Azure subscription
- A GitHub account
- Sufficient Azure AD permissions to create service principals and security groups

---

## First-time setup

### 1. Log in to Azure

```powershell
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 2. Create the Terraform state storage account

Terraform stores its state remotely in Azure Blob Storage. Create this once — it is not managed by Terraform itself.

```powershell
az group create --name rg-terraform-state --location uksouth

az storage account create `
  --name stterraformstateyourname `
  --resource-group rg-terraform-state `
  --location uksouth `
  --sku Standard_LRS

az storage container create `
  --name tfstate `
  --account-name stterraformstateyourname
```

### 3. Create the GitHub Actions service principal and federated identity(OIDC)

```powershell
$SUBSCRIPTION_ID = az account show --query id --output tsv

az ad sp create-for-rbac `
  --name "sp-hello-world-github" `
  --role Contributor `
  --scopes /subscriptions/$SUBSCRIPTION_ID `

$SP_APP_ID = az ad sp list `
  --display-name "sp-hello-world-github" `
  --query "[0].appId" --output tsv

# Write the federated credential definition to a temp file
$credentialJson = @{
    name        = "github-main"
    issuer      = "https://token.actions.githubusercontent.com"
    subject     = "repo:YOUR_GITHUB_USERNAME/hello-world-azure:ref:refs/heads/main"
    description = "GitHub Actions — main branch"
    audiences   = @("api://AzureADTokenExchange")
} | ConvertTo-Json

$tempFile = New-TemporaryFile
$credentialJson | Out-File -FilePath $tempFile.FullName -Encoding utf8

# Pass the file path instead of an inline JSON string
az ad app federated-credential create `
  --id $SP_APP_ID `
  --parameters $tempFile.FullName

# Clean up
Remove-Item $tempFile.FullName

# Verify
az ad app federated-credential list `
  --id $SP_APP_ID `
  --output table
```

Note: The subject field of the credential(e.g.: "repo:YOUR_GITHUB_USERNAME/hello-world-azure:ref:refs/heads/main") needs to match exactly the name of the repo and branch as it's case sensitive.

### 4. Create the Entra SQL admin security group

The SQL Server's Entra admin is a security group containing both your personal user and the GitHub Actions service principal. This allows the pipeline to connect to the database via Azure AD to provision the API's Managed Identity as a DB user.

```powershell
$group = az ad group create `
  --display-name "sql-admins-hello-world" `
  --mail-nickname "sql-admins-hello-world" | ConvertFrom-Json

# Add your personal user
$myObjectId = az ad user show `
  --id you@yourdomain.com `
  --query id --output tsv
az ad group member add --group $group.id --member-id $myObjectId

# Add the service principal
$spObjectId = az ad sp list `
  --display-name "sp-hello-world-github" `
  --query "[0].id" --output tsv
az ad group member add --group $group.id --member-id $spObjectId

echo "Group ID: $($group.id)"
```

### 5. Add GitHub Actions secrets

Go to your repository → **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | `clientId` from the JSON |
| `AZURE_SUBSCRIPTION_ID` | `subscriptionId` from the JSON |
| `AZURE_TENANT_ID` | `tenantId` from the JSON |
| `TF_STATE_RESOURCE_GROUP` | `rg-terraform-state` |
| `TF_STATE_STORAGE_ACCOUNT` | Your state storage account name |
| `TF_STATE_CONTAINER` | `tfstate` |
| `ACR_NAME` | Your ACR name |
| `WEB_APP_NAME` | Your web App Service name |
| `API_APP_NAME` | Your API App Service name |
| `SQL_SERVER_NAME` | Your SQL server name |
| `SQL_DATABASE_NAME` | `sqldb-hello-world` |
| `SQL_ADMIN_PASSWORD` | Your SQL admin password |
| `SQL_ADMIN_LOGIN` | Your SQL admin user |
| `SQL_ENTRA_ADMIN_GROUP_NAME` | `sql-admins-hello-world` |
| `SQL_ENTRA_ADMIN_OBJECT_ID` | The security group object ID |
| `ALERT_EMAIL` | Email address for DTU alerts |
| `RESOURCE_GROUP_NAME` | Name of the resource group where the infrastructure will be deployed |

### 6. Grant Directory Readers to the SQL server identity

This step must be performed after the deployment of the infratructure, as it requires the SQL server's system-assigned identity to have reader permissions to Microsoft Graph. This is needed as and when the Github Actions service principal creates a login and user on the SQL database that will be mapped to the API's service principal. 

The why and how the above can be achieved is explained by following the below links:
https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-service-principal?view=azuresql
https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity?view=azuresql

This only needs to be done once.

---

## Deployment

### First deployment

Run the workflows in this order:

**1. Infrastructure pipeline** — provisions all Azure resources:

Go to **Actions → Infrastructure — Terraform → Run workflow**

This creates the VNet, subnets, App Gateway, both App Services, SQL Server, SQL Database, Application Insights instances, Log Analytics workspace, alert rule, and action group. Takes approximately 5–10 minutes.

**2. After infra completes** — grant Directory Readers to the SQL server identity (see step 6 above).

**3. Application pipeline** — builds and deploys both Docker images:

Go to **Actions → Application — Build & Deploy → Run workflow**

This builds the web and API Docker images, pushes them to ACR, deploys both to their App Services, then runs the SQL setup script to grant the API's Managed Identity `db_datareader` and `db_datawriter` access.

### Subsequent deployments

Pushes to `main` trigger pipelines automatically:

| Changed files | Pipeline triggered |
|---|---|
| `terraform/**` | Infrastructure — Terraform |
| `app/**` | Application — Build & Deploy |

---

## Verifying the deployment

Get the App Gateway public IP:

```powershell
cd terraform
terraform output app_gateway_public_ip
```

Open `http://<IP_ADDRESS>` in a browser. You should see the Hello World page with a green "Connected" status card confirming the API has successfully reached the database.

You can also verify individual components directly:

```powershell
# Web app health check
curl https://YOUR_WEB_APP_NAME.azurewebsites.net/health

# API health check
curl https://YOUR_API_APP_NAME.azurewebsites.net/health

# API database connectivity check
curl https://YOUR_API_APP_NAME.azurewebsites.net/db-check
```

## Azure resources provisioned

| Resource | Name pattern | Purpose |
|---|---|---|
| Resource Group | `rg-hello-world` | Container for all app resources |
| Container Registry | `acrheloworldyourname` | Private Docker image store |
| Virtual Network | `vnet-hello-world` | Private network for all services |
| App Gateway | `agw-hello-world` | Public HTTPS entry point |
| App Service Plan | `asp-hello-world` | Shared compute for both app services |
| Web App Service | `web-hello-world-yourname` | Hosts the Flask web app container |
| API App Service | `api-hello-world-yourname` | Hosts the Flask API container |
| App Insights (web) | `appi-web-hello-world` | Telemetry for the web app |
| App Insights (API) | `appi-api-hello-world` | Telemetry for the API |
| Log Analytics | `log-hello-world` | Centralised log storage |
| SQL Server | `sql-hello-world-yourname` | Logical SQL server |
| SQL Database | `sqldb-hello-world` | Basic tier, 5 DTUs |
| Metric Alert | `alert-dtu-85pct` | Fires at 85% DTU for 20 minutes |
| Action Group | `ag-hello-world-dtu-alert` | Email notification on alert |

---

## Security notes

- The API authenticates to the SQL database exclusively via **Managed Identity** — no passwords in code or configuration
- The SQL server's Entra admin is a **security group**, not an individual account or the application identity
- The API's Managed Identity is granted only `db_datareader` and `db_datawriter` — no admin rights
- The SQL server has a **system-assigned identity** with Directory Readers to resolve Entra objects
- App Services enforce **HTTPS only**
- Both App Services use **VNet integration** — outbound traffic stays within the private network
- Terraform state is stored in **Azure Blob Storage** with restricted RBAC access
- All secrets are stored in **GitHub Actions secrets** — never in code or `.tfvars` files committed to the repository