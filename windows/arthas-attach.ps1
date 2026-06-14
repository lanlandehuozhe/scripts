<#
.SYNOPSIS
  Attach Arthas to any Java process (including WinSW SYSTEM processes)
.DESCRIPTION
  1. List all Java processes with PID/name/user
  2. Let user pick PID
  3. Attach Arthas (admin privilege is enough, no PsExec needed)
#>

Write-Host "========== Java Processes ==========" -ForegroundColor Cyan
$javaProcs = tasklist /fi "imagename eq java.exe" /v /fo csv 2>$null | ConvertFrom-Csv
$procs = @()
$jpsOut = jps -l 2>$null
$pidName = @{}
if ($jpsOut) {
    $jpsOut | ForEach-Object {
        $parts = $_ -split ' ', 2
        if ($parts.Count -eq 2) { $pidName[$parts[0]] = $parts[1] }
    }
}

$index = 0
foreach ($p in $javaProcs) {
    $pidVal = $p.PID
    $name = if ($pidName.ContainsKey($pidVal)) { $pidName[$pidVal] } else { "unknown" }
    Write-Host "  [$index] PID=$pidVal  $name" -ForegroundColor Yellow
    $procs += @{procId=$pidVal; procName=$name}
    $index++
}

if ($procs.Count -eq 0) {
    Write-Host "[ERROR] No Java processes found" -ForegroundColor Red
    exit 1
}

$inputIdx = Read-Host "`nSelect PID [0-$($procs.Count-1)]"
$sel = $procs[[int]$inputIdx]
Write-Host "Attaching to PID $($sel.procId): $($sel.procName)" -ForegroundColor Green
Write-Host ""

$arthasJar = "C:\tools\arthas-boot.jar"
if (-not (Test-Path $arthasJar)) {
    Write-Host "Downloading Arthas..." -ForegroundColor Cyan
    iwr -Uri "https://arthas.aliyun.com/arthas-boot.jar" -OutFile $arthasJar
}

java -jar $arthasJar $sel.procId
