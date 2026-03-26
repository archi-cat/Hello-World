<#
.SYNOPSIS
    Grants the API's Managed Identity least-privilege access to the SQL database.

.DESCRIPTION
    Connects to the SQL database using SQL admin credentials and:
      1. Creates an external user mapped to the API's Managed Identity
      2. Grants db_datareader — allows SELECT on all tables
      3. Grants db_datawriter — allows INSERT, UPDATE, DELETE on all tables

    This script is idempotent — safe to run multiple times. If the user
    already exists the CREATE USER statement is skipped gracefully.

.NOTES
    Requires the SqlServer PowerShell module.
    Runs as a step in the GitHub Actions deploy workflow after Terraform apply.
#>

param (
    [Parameter(Mandatory)] [string]       $SqlServerFqdn,
    [Parameter(Mandatory)] [string]       $SqlDatabaseName,
    [Parameter(Mandatory)] [string]       $SqlAdminLogin,
    [Parameter(Mandatory)] [SecureString] $SqlAdminPassword,
    [Parameter(Mandatory)] [string]       $ApiAppServiceName
)

# Install SqlServer module if not already present
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "Installing SqlServer module..."
    Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
}

Import-Module SqlServer

# Mark the SecureString as read-only — required by SqlCredential
$SqlAdminPassword.MakeReadOnly()

# Build a SqlCredential from the login and SecureString password —
# the password is never decrypted to a plain string at any point
$sqlCredential = New-Object System.Data.SqlClient.SqlCredential(
    $SqlAdminLogin,
    $SqlAdminPassword
)

$connectionString = "Server=$SqlServerFqdn;Database=$SqlDatabaseName;" +
                    "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

Write-Host "Connecting to $SqlServerFqdn / $SqlDatabaseName..."

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection(
        $connectionString,
        $sqlCredential
    )
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