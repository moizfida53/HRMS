<#
  HRMS - set the database connection on this server.

  Asks for the SQL Server, the database and how to sign in, tests the connection,
  then writes dbsettings.json next to HRMS.Web.dll (this script's folder). The site
  picks it up straight away - no restart. Run it again any time to change it.
  Publishing the project never overwrites dbsettings.json.
#>
$ErrorActionPreference = 'Stop'
$folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$file   = Join-Path $folder 'dbsettings.json'

function Ask([string]$label, [string]$default) {
    $hint = if ($default) { " [$default]" } else { '' }
    $value = Read-Host "$label$hint"
    if ([string]::IsNullOrWhiteSpace($value)) { return $default }
    return $value.Trim()
}

Write-Host ''
Write-Host '  HRMS - database connection' -ForegroundColor Cyan
Write-Host "  Saved to: $file"
Write-Host ''

# the current values, as defaults
$current = $null
if (Test-Path $file) {
    try {
        $json = Get-Content $file -Raw | ConvertFrom-Json
        $current = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($json.ConnectionStrings.SqlServerConnectionString)
        Write-Host '  A connection is already set - press Enter to keep a value.' -ForegroundColor DarkGray
    } catch { $current = $null }
}

$server   = Ask 'SQL Server (e.g. SQLSERVER or SQLSERVER\INSTANCE or 10.0.0.5,1433)' $(if ($current) { $current.DataSource } else { '' })
while (-not $server) { $server = Ask 'SQL Server' '' }
$database = Ask 'Database' $(if ($current -and $current.InitialCatalog) { $current.InitialCatalog } else { 'HRMS_Kuwait' })

$windows = (Ask 'Sign in with Windows (the IIS app pool account)? Y/N' $(if ($current -and $current.IntegratedSecurity) { 'Y' } else { 'N' })) -match '^[Yy]'

$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$b['Data Source'] = $server
$b['Initial Catalog'] = $database
if ($windows) {
    $b['Integrated Security'] = $true
} else {
    $user = Ask 'SQL user name' $(if ($current -and $current.UserID) { $current.UserID } else { '' })
    while (-not $user) { $user = Ask 'SQL user name' '' }
    $secure = Read-Host 'Password (leave empty to keep the current one)' -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if (-not $plain -and $current) { $plain = $current.Password }
    $b['User ID'] = $user
    $b['Password'] = $plain
}

$trust = (Ask 'Trust the SQL Server certificate (Y unless it has a certificate from a trusted authority)? Y/N' 'Y') -match '^[Yy]'

# test it (same encryption the site uses)
$test = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($b.ConnectionString)
$test['Encrypt'] = $true
$test['TrustServerCertificate'] = $trust
$test['Connect Timeout'] = 15
Write-Host ''
Write-Host '  Testing the connection...' -NoNewline
try {
    $c = New-Object System.Data.SqlClient.SqlConnection($test.ConnectionString)
    $c.Open()
    $cmd = $c.CreateCommand()
    $cmd.CommandText = "SELECT CASE WHEN OBJECT_ID(N'Security.Users') IS NULL THEN 0 ELSE 1 END"
    $hasTables = [int]$cmd.ExecuteScalar()
    $c.Close()
    Write-Host ' OK' -ForegroundColor Green
    if ($hasTables -eq 0) { Write-Host '  Note: the database has no HRMS tables yet - run the db/ scripts on it.' -ForegroundColor Yellow }
} catch {
    Write-Host ' FAILED' -ForegroundColor Red
    Write-Host "  $($_.Exception.InnerException.Message)$($_.Exception.Message)" -ForegroundColor Red
    if ((Ask 'Save it anyway? Y/N' 'N') -notmatch '^[Yy]') { Write-Host '  Nothing saved.'; exit 1 }
}

$settings = [ordered]@{
    ConnectionStrings = [ordered]@{ SqlServerConnectionString = $b.ConnectionString }
    Database          = [ordered]@{ TrustServerCertificate = $trust }
}
[IO.File]::WriteAllText($file, ($settings | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "  Saved: $file" -ForegroundColor Green
Write-Host '  The site uses it straight away - refresh the browser.'
Write-Host '  Keep this file private: it holds the database password.'
Write-Host ''
