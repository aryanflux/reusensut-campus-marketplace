param(
    [ValidateSet("demo", "menu", "workflow", "web")]
    [string]$Action = "demo"
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mysqlBase = "C:\Program Files\MySQL\MySQL Server 8.0"
$mysqlBin = Join-Path $mysqlBase "bin"
$mysqld = Join-Path $mysqlBin "mysqld.exe"
$mysql = Join-Path $mysqlBin "mysql.exe"
$mysqladmin = Join-Path $mysqlBin "mysqladmin.exe"
$dataDir = Join-Path (Join-Path $env:LOCALAPPDATA "ReUseNSUT") "mysql_data"
$legacyDataDir = Join-Path $projectDir "mysql_data"
$port = 3307
$serverArguments = '--datadir="{0}" --basedir="{1}" --port={2} --bind-address=127.0.0.1 --console' -f $dataDir, $mysqlBase, $port

function Normalize-DirectoryPath([string]$Path) {
    $normalized = [Environment]::ExpandEnvironmentVariables($Path.Trim()).Replace('\\', '\')
    return [IO.Path]::GetFullPath($normalized).TrimEnd([char[]]@('\', '/'))
}

foreach ($path in @($mysqld, $mysql, $mysqladmin)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "MySQL executable not found: $path. Install MySQL Server 8.0 or update the MySQL path in run-project.ps1."
    }
}

Set-Location $projectDir
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$mysqlSystemDir = Join-Path $dataDir "mysql"
if (-not (Test-Path -LiteralPath $mysqlSystemDir)) {
    $existingFiles = @(Get-ChildItem -LiteralPath $dataDir -Force)
    if ($existingFiles.Count -gt 0) {
        throw "The local MySQL data folder is not initialized and is not empty: $dataDir. Move its contents to a backup folder before retrying."
    }
    Write-Host "Initializing the project's local MySQL data folder..."
    & $mysqld --initialize-insecure "--datadir=$dataDir" "--basedir=$mysqlBase"
    if ($LASTEXITCODE -ne 0) {
        throw "MySQL initialization failed. Check the MySQL installation and write permissions for $dataDir."
    }
}

$env:DB_HOST = "127.0.0.1"
$env:DB_PORT = [string]$port
$env:DB_USER = "root"
$env:DB_PASSWORD = ""

function Test-ProjectMySql {
    try {
        $null = & $mysqladmin @pingArgs 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

$serverStartedHere = $false
$dbProcess = $null
$serverAlreadyRunning = $false
$pingArgs = @("--host=127.0.0.1", "--port=$port", "--user=root", "ping")
if (Test-ProjectMySql) {
    $reportedDataDir = & $mysql "--host=127.0.0.1" "--port=$port" "--user=root" "--batch" "--skip-column-names" "--execute=SELECT @@datadir"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not identify the MySQL server already running on port $port."
    }
    $reportedDataDir = Normalize-DirectoryPath $reportedDataDir
    $expectedDataDir = Normalize-DirectoryPath $dataDir
    $legacyProjectDataDir = Normalize-DirectoryPath $legacyDataDir
    if ($reportedDataDir -ieq $expectedDataDir) {
        $serverAlreadyRunning = $true
        Write-Host "Using the project's MySQL server already running on port $port."
    } elseif ($reportedDataDir -ieq $legacyProjectDataDir) {
        $connections = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
        $legacyServer = $false
        $legacyServerProcessId = $null
        foreach ($connection in $connections) {
            $processInfo = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $connection.OwningProcess) -ErrorAction SilentlyContinue
            if ($processInfo.ExecutablePath -ieq $mysqld -and $processInfo.CommandLine -like "*$legacyProjectDataDir*") {
                $legacyServer = $true
                $legacyServerProcessId = $connection.OwningProcess
            }
        }
        if (-not $legacyServer) {
            throw "Port $port uses the old project data folder, but its server process could not be verified. Stop it manually before rerunning."
        }
        Write-Host "Stopping the project's old MySQL server from the OneDrive data folder..."
        & $mysqladmin "--host=127.0.0.1" "--port=$port" "--user=root" shutdown
        if ($LASTEXITCODE -ne 0) {
            throw "Could not safely stop the verified old project MySQL server."
        }
        for ($attempt = 0; $attempt -lt 20 -and (Get-Process -Id $legacyServerProcessId -ErrorAction SilentlyContinue); $attempt++) {
            Start-Sleep -Seconds 1
        }
        if (Get-Process -Id $legacyServerProcessId -ErrorAction SilentlyContinue) {
            throw "The old project MySQL server did not stop. Stop it before retrying."
        }
    } else {
        throw "Port $port is already serving a different MySQL instance. Stop that instance or change the project port in run-project.ps1 and main.py."
    }
}

if (-not $serverAlreadyRunning) {
    $stdoutLog = Join-Path $dataDir "mysqld-console.log"
    $stderrLog = Join-Path $dataDir "mysqld-error.log"
    $dbProcess = Start-Process -FilePath $mysqld `
        -ArgumentList $serverArguments `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    $serverStartedHere = $true

    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Seconds 1
        if ($dbProcess.HasExited) {
            $details = if (Test-Path -LiteralPath $stderrLog) { Get-Content -LiteralPath $stderrLog -Raw } else { "No MySQL error log was created." }
            throw "The local MySQL server stopped during startup.`n$details"
        }
        if (Test-ProjectMySql) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw "MySQL did not become ready on port $port. Check $stderrLog."
    }
    Write-Host "Started the project's local MySQL server on port $port."
}

$databaseExists = & $mysql "--host=127.0.0.1" "--port=$port" "--user=root" "--batch" "--skip-column-names" "--execute=SHOW DATABASES LIKE 'reusensut'"
if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the local MySQL databases. Check the MySQL logs in $dataDir."
}
$schemaDir = Join-Path $dataDir "reusensut"
if (-not $databaseExists -and (Test-Path -LiteralPath $schemaDir)) {
    if (-not $serverStartedHere) {
        throw "An orphaned reusensut folder was found while MySQL is already running. Stop the project MySQL with .\stop-project-db.ps1, then rerun this script."
    }

    Write-Host "Backing up the orphaned database folder before rebuilding..."
    & $mysqladmin "--host=127.0.0.1" "--port=$port" "--user=root" shutdown
    if ($LASTEXITCODE -ne 0) {
        throw "Could not safely stop the local MySQL server to recover the orphaned schema folder."
    }
    $dbProcess.WaitForExit()
    $backupDir = Join-Path $dataDir ("reusensut_orphan_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    Move-Item -LiteralPath $schemaDir -Destination $backupDir

    $dbProcess = Start-Process -FilePath $mysqld `
        -ArgumentList $serverArguments `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Seconds 1
        if ($dbProcess.HasExited) {
            throw "MySQL stopped while restarting after recovery. Check $stderrLog."
        }
        if (Test-ProjectMySql) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw "MySQL did not restart after recovery. Check $stderrLog."
    }
    Write-Host "Orphaned schema backed up to $backupDir."
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    throw "Python was not found. Activate the project's virtual environment or install Python, then rerun this script."
}

& $env:ComSpec /d /c 'python -c "import flask, mysql.connector" >nul 2>&1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing the Python MySQL connector..."
    & python -m pip install -r (Join-Path $projectDir "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install Python requirements. Check that Python and pip are installed."
    }
}

Write-Host "Setting up the project database..."
python main.py setup
if ($LASTEXITCODE -ne 0) {
    throw "Project setup failed. Fix the reported database error before running the demo."
}

if ($Action -eq "web") {
    python web_app.py
} elseif ($Action -eq "demo") {
    python main.py demo
} else {
    python main.py $Action
}
if ($LASTEXITCODE -ne 0) {
    throw "The project command '$Action' failed."
}

Write-Host "`nMySQL remains running on port $port. Use python main.py menu or python main.py workflow in this terminal."
