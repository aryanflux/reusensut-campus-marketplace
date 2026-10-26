$ErrorActionPreference = "Stop"
$mysqladmin = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqladmin.exe"
if (-not (Test-Path -LiteralPath $mysqladmin)) {
    throw "MySQL CLI not found: $mysqladmin"
}

& $mysqladmin --host=127.0.0.1 --port=3307 --user=root shutdown
if ($LASTEXITCODE -ne 0) {
    throw "Could not stop the project MySQL server. It may not be running on port 3307."
}
Write-Host "Stopped the project's local MySQL server."
