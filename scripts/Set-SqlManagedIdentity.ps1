<#
.SYNOPSIS
    Grants the API's Managed Identity least-privilege access to the SQL database.

.DESCRIPTION
    Connects to the SQL database using an Azure AD access token obtained from
    the Azure CLI (the runner is already authenticated via azure/login) and:
      1. Creates an external user mapped to the API's Managed Identity
      2. Grants db_datareader — allows SELECT on all tables
      3. Grants db_datawriter — allows INSERT, UPDATE, DELETE on all tables

    This script is idempotent — safe to run multiple times. If the user
    already exists the CREATE USER statement is skipped gracefully.

.NOTES
    Requires the Az CLI to be logged in (handled by azure/login in the workflow).
    Runs as a step in the GitHub Actions deploy workflow after Terraform apply.
#>

param (
    [Parameter(Mandatory)] [string] $SqlServerFqdn,
    [Parameter(Mandatory)] [string] $SqlDatabaseName,
    [Parameter(Mandatory)] [string] $ApiAppServiceName
)

# Install SqlServer module if not already present
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "Installing SqlServer module..."
    Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
}

Import-Module SqlServer

# Obtain an Azure AD access token for the SQL Database resource.
# The runner is already authenticated via the azure/login workflow step.
Write-Host "Obtaining Azure AD access token for SQL Database..."
$tokenJson    = az account get-access-token --resource https://database.windows.net/ | ConvertFrom-Json
$accessToken  = $tokenJson.accessToken

if (-not $accessToken) {
    Write-Error "Failed to obtain Azure AD access token. Ensure azure/login step has run."
    exit 1
}

# Build connection string — no credentials here, auth is via the token
$connectionString = "Server=$SqlServerFqdn;Database=$SqlDatabaseName;" +
                    "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

Write-Host "Connecting to $SqlServerFqdn / $SqlDatabaseName..."

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString

    # Attach the Azure AD token to the connection
    $connection.AccessToken = $accessToken
    $connection.Open()
    Write-Host "Connected successfully."

    # Check if the user already exists — makes the script idempotent
    $checkQuery = "SELECT COUNT(*) FROM sys.database_principals WHERE name = '$ApiAppServiceName'"
    $checkCmd   = New-Object System.Data.SqlClient.SqlCommand $checkQuery, $connection
    $userExists = $checkCmd.ExecuteScalar()

    if ($userExists -eq 0) {
        Write-Host "Creating external user for Managed Identity: $ApiAppServiceName"
        $createCmd = New-Object System.Data.SqlClient.SqlCommand `
            "CREATE USER [$ApiAppServiceName] FROM EXTERNAL PROVIDER", $connection
        $createCmd.ExecuteNonQuery() | Out-Null
        Write-Host "User created."
    } else {
        Write-Host "User $ApiAppServiceName already exists — skipping CREATE USER."
    }

    # Grant least-privilege roles
    Write-Host "Granting db_datareader to $ApiAppServiceName..."
    $readerCmd = New-Object System.Data.SqlClient.SqlCommand `
        "ALTER ROLE db_datareader ADD MEMBER [$ApiAppServiceName]", $connection
    $readerCmd.ExecuteNonQuery() | Out-Null

    Write-Host "Granting db_datawriter to $ApiAppServiceName..."
    $writerCmd = New-Object System.Data.SqlClient.SqlCommand `
        "ALTER ROLE db_datawriter ADD MEMBER [$ApiAppServiceName]", $connection
    $writerCmd.ExecuteNonQuery() | Out-Null

    Write-Host "Done. $ApiAppServiceName has been granted db_datareader and db_datawriter."

} catch {
    Write-Error "Script failed: $_"
    exit 1
} finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
}