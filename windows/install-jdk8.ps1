<#
.SYNOPSIS
  Install JDK 8 (Adoptium Temurin) on Windows
.DESCRIPTION
  1. Download JDK 8 MSI from official GitHub
  2. Silent install to C:\Java\jdk8
  3. Set JAVA_HOME and update PATH (Machine scope)
  4. Verify installation
  5. (Optional) Download arthas-boot.jar + desktop shortcut
.USAGE
  powershell -File install-jdk8.ps1              # Full install
  powershell -File install-jdk8.ps1 -SkipArthas  # No Arthas
#>

param([switch]$SkipArthas)
$ErrorActionPreference = "Stop"
$JDK_DIR = "C:\Java\jdk8"
$MSI = "$env:TEMP\jdk8.msi"
$JAR_DIR = "C:\tools"

Write-Host "========== [1/3] Download JDK 8 ==========" -ForegroundColor Cyan
Write-Host "Source: adoptium/temurin8-binaries (jdk8u402-b06)"

try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u402-b06/OpenJDK8U-jdk_x64_windows_hotspot_8u402b06.msi", $MSI)
    Write-Host "Downloaded: $MSI ($((Get-Item $MSI).Length / 1MB -as [int]) MB)"
} catch {
    Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
    Write-Host "Trying mirror..."
    $wc.DownloadFile("https://mirrors.cloud.tencent.com/Adoptium/8/jdk/x64/windows/OpenJDK8U-jdk_x64_windows_hotspot_8u402b06.msi", $MSI)
    Write-Host "Downloaded from mirror"
}

Write-Host "========== [2/3] Install JDK 8 ==========" -ForegroundColor Cyan
Write-Host "Target: $JDK_DIR"

if (-not (Test-Path $JDK_DIR)) {
    $proc = Start-Process msiexec -ArgumentList "/i `"$MSI`" /quiet INSTALLDIR=`"$JDK_DIR`" ADDLOCAL=ALL" -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Host "[ERROR] Install failed (exit: $($proc.ExitCode))" -ForegroundColor Red
        exit 1
    }
    Write-Host "Install OK (exit: $($proc.ExitCode))"
} else {
    Write-Host "[SKIP] $JDK_DIR already exists"
}

Write-Host "========== [3/3] Set Environment Variables ==========" -ForegroundColor Cyan
try {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JDK_DIR, "Machine")
    Write-Host "JAVA_HOME -> $JDK_DIR"
} catch {
    Write-Host "[ERROR] Set JAVA_HOME failed (need Admin?)" -ForegroundColor Yellow
}

$curPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$binDir = "$JDK_DIR\bin"
if ($curPath -notlike "*$binDir*") {
    try {
        [Environment]::SetEnvironmentVariable("PATH", "$binDir;$curPath", "Machine")
        Write-Host "PATH  -> added $binDir"
    } catch {
        Write-Host "[ERROR] Set PATH failed (need Admin?)" -ForegroundColor Yellow
    }
}

# Current session
$env:JAVA_HOME = $JDK_DIR
$env:Path = "$binDir;$env:Path"

Write-Host ============================================ -ForegroundColor Green
Write-Host " Verifying..." -ForegroundColor Green
Write-Host ============================================ -ForegroundColor Green
$ver = java -version 2>&1
Write-Host $ver

java -version 2>&1 | Select-String "version" | ForEach-Object {
    Write-Host "JDK 8 installation OK: $_" -ForegroundColor Green
}

# Cleanup
Remove-Item $MSI -Force -ErrorAction SilentlyContinue

# Optional: Arthas
if (-not $SkipArthas) {
    Write-Host ""
    Write-Host "========== [Optional] Arthas ==========" -ForegroundColor Cyan
    if (-not (Test-Path $JAR_DIR)) { New-Item -ItemType Directory -Path $JAR_DIR -Force | Out-Null }

    $arthasJar = "$JAR_DIR\arthas-boot.jar"
    if (-not (Test-Path $arthasJar)) {
        $wc.DownloadFile("https://arthas.aliyun.com/arthas-boot.jar", $arthasJar)
        Write-Host "Arthas downloaded: $arthasJar"
    } else {
        Write-Host "[SKIP] Arthas already exists"
    }

    $lnk = "$env:USERPROFILE\Desktop\Arthas.lnk"
    if (-not (Test-Path $lnk)) {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $s.TargetPath = "$binDir\javaw.exe"
        $s.Arguments = "-jar $arthasJar"
        $s.WorkingDirectory = $JAR_DIR
        $s.Save()
        Write-Host "Desktop shortcut created: $lnk"
    } else {
        Write-Host "[SKIP] Desktop shortcut already exists"
    }
}

Write-Host ""
Write-Host "========== Complete ==========" -ForegroundColor Green
Write-Host "JAVA_HOME: $JDK_DIR"
Write-Host "Java:      $(Get-Command java.exe | Select-Object -ExpandProperty Source)"
if (-not $SkipArthas) {
    Write-Host "Arthas:    $JAR_DIR\arthas-boot.jar"
    Write-Host "Shortcut:  $env:USERPROFILE\Desktop\Arthas.lnk"
}
