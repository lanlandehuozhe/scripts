<#
.SYNOPSIS
  Parking Authorization Update Script
.DESCRIPTION
  1. Update PostgreSQL authorization expiry
  2. Restart ParkServer & park_client
  3. Log results
.USAGE
  powershell -File park-update.ps1          # Full run
  powershell -File park-update.ps1 -DryRun  # Show what would be done
#>

param([switch]$DryRun)

$PG_HOST = "127.0.0.1"
$PG_PORT = 5488
$PG_USER = "postgres"
$PG_DB  = "zc_parking_server"
$PG_PASS = "abc123"
$DEFAULT_DIRS = @(
    "D:\Park智慧停车\park\bin-client",
    "D:\Park智慧停车\park\bin",
    "C:\Park\park\bin-client"
)

$LOG_DIR = "$env:USERPROFILE\park_updates"
$TS = Get-Date -Format "yyyyMMdd_HHmmss"
$LOG_FILE = "$LOG_DIR\update_$TS.log"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    $line | Out-File -FilePath $LOG_FILE -Encoding Default -Append
    Write-Host $line
}

# ==========================================
# Step 1: SQL Update
# ==========================================
Write-Log "========== [1/3] Authorization SQL =========="
Write-Log "Target: $PG_DB @ ${PG_HOST}:${PG_PORT}"

$SQL_FILE = "$env:TEMP\park_auth_$TS.sql"
@"
UPDATE tb_sys_customer
SET mix_info = '{"exp": "2056-08-07 23:59:59", "sign": "71fb68e148d2123379babef3af98359c", "first": "2056-06-08 09:34:31", "latest": "2026-06-08 09:39:25"}'
WHERE id = 1;
"@ | Out-File -FilePath $SQL_FILE -Encoding ASCII

if ($DryRun) {
    Write-Log "[DRY RUN] SQL would be:"
    Get-Content $SQL_FILE | ForEach-Object { Write-Log "  $_" }
} else {
    $env:PGPASSWORD = $PG_PASS
    $result = psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -f $SQL_FILE 2>&1
    $env:PGPASSWORD = ""
    if ($LASTEXITCODE -eq 0) {
        Write-Log "SQL UPDATE OK"
    } else {
        Write-Log "[ERROR] SQL failed: $result"
        Write-Log "Check: PostgreSQL running? PGPASSWORD correct?"
    }
}

if (Test-Path $SQL_FILE) { [System.IO.File]::Delete($SQL_FILE) }

# ==========================================
# Step 2: Find, Stop, Start Services
# ==========================================
Write-Log "========== [2/3] Stop Services =========="

$psRunning = Get-Process -Name "ParkServer" -ErrorAction SilentlyContinue | Select-Object -First 1
$pcRunning = Get-Process -Name "park_client" -ErrorAction SilentlyContinue | Select-Object -First 1

# Determine paths
$psPath = if ($psRunning) { $psRunning.Path } else { $null }
$pcPath = if ($pcRunning) { $pcRunning.Path } else { $null }

if (-not $psPath) {
    foreach ($d in $DEFAULT_DIRS) {
        $p = Join-Path $d "ParkServer.exe"
        if (Test-Path $p) { $psPath = $p; break }
    }
}
if (-not $pcPath) {
    foreach ($d in $DEFAULT_DIRS) {
        $p = Join-Path $d "park_client.exe"
        if (Test-Path $p) { $pcPath = $p; break }
    }
}

if ($psPath) { Write-Log "ParkServer path: $psPath" } else { Write-Log "[WARN] ParkServer.exe not found" }
if ($pcPath) { Write-Log "park_client path: $pcPath" } else { Write-Log "[WARN] park_client.exe not found" }

if ($DryRun) {
    Write-Log "[DRY RUN] Would stop and restart processes"
    Write-Log "========== Complete (Dry Run) =========="
    exit 0
}

# Stop
if ($psRunning) {
    Stop-Process -Id $psRunning.Id -Force
    Write-Log "ParkServer (PID $($psRunning.Id)) stopped"
} else { Write-Log "[INFO] ParkServer not running" }

if ($pcRunning) {
    Stop-Process -Id $pcRunning.Id -Force
    Write-Log "park_client (PID $($pcRunning.Id)) stopped"
} else { Write-Log "[INFO] park_client not running" }

Start-Sleep -Seconds 3

# Start
Write-Log "========== [3/3] Start Services =========="
$started = @{}

if ($psPath -and (Test-Path $psPath)) {
    $dir = Split-Path $psPath -Parent
    Push-Location $dir
    Start-Process -FilePath $psPath -WindowStyle Hidden
    Pop-Location
    Write-Log "ParkServer starting from: $dir"
    $started["ParkServer"] = $true
} else { Write-Log "[ERROR] ParkServer.exe not found, cannot start" }

Start-Sleep -Seconds 8

if ($pcPath -and (Test-Path $pcPath)) {
    $dir = Split-Path $pcPath -Parent
    Push-Location $dir
    Start-Process -FilePath $pcPath -WindowStyle Hidden
    Pop-Location
    Write-Log "park_client starting from: $dir"
    $started["park_client"] = $true
} else { Write-Log "[ERROR] park_client.exe not found, cannot start" }

Start-Sleep -Seconds 5

# Verify
Write-Log "========== Verification =========="
$psNow = Get-Process -Name "ParkServer" -ErrorAction SilentlyContinue
$pcNow = Get-Process -Name "park_client" -ErrorAction SilentlyContinue

if ($psNow) { Write-Log "OK: ParkServer running (PID $($psNow.Id))" } else { Write-Log "[ERROR] ParkServer FAILED to start" }
if ($pcNow) { Write-Log "OK: park_client running (PID $($pcNow.Id))" } else { Write-Log "[ERROR] park_client FAILED to start" }

Write-Log "========== Complete =========="
Write-Host ""
Write-Host "Log: $LOG_FILE"
