#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 服务端一键部署：OpenSSH Server + 反向隧道 (34 中继)
.DESCRIPTION
    自动完成：
      1. 安装 OpenSSH Server + Client
      2. 配置 sshd (开机自启、防火墙放行 22 端口)
      3. 确保 qcjc 管理员用户存在
      4. 部署 SSH 隧道密钥
      5. 启动反向隧道 + 注册每 5 分钟保活计划任务

    用法：powershell -ExecutionPolicy Bypass -File install-windows-endpoint.ps1
.PARAMETER TunnelUser
    隧道用户名（默认 tunnel）
.PARAMETER TunnelHost
    隧道中继服务器（默认 124.222.125.34）
.PARAMETER TunnelPort
    隧道本地端口（默认 22200，铜梁 1.4 已占用，新车场从 22201 起）
#>
param(
    [string]$TunnelUser = "tunnel",
    [string]$TunnelHost = "124.222.125.34",
    [int]$TunnelPort = 22201
)

$ErrorActionPreference = "Stop"
$ScriptDir = Join-Path $env:USERPROFILE "scripts"
$KeyFile = Join-Path $ScriptDir "tunnel_id_ed25519"
$KeepAliveScript = Join-Path $ScriptDir "tunnel-keepalive.ps1"
$SetupLog = Join-Path $ScriptDir "endpoint-setup.log"
$TaskName = "ReverseTunnel-to-34"

function Log {
    param([string]$Msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time $Msg" | Out-File -FilePath $SetupLog -Encoding UTF8 -Append
    Write-Host "$time $Msg"
}

function Write-Banner {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Windows 服务端一键部署" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  隧道: ${TunnelUser}@${TunnelHost}:${TunnelPort}"
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
# Step 1: Install OpenSSH
# ============================================================
function Install-OpenSSH {
    param([string]$Name)
    $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "$Name*" }
    if ($cap.State -eq "Installed") {
        Log "[OK] $Name already installed"
        return $true
    }
    Log "[..] Installing $Name ..."
    try {
        $cap | Add-WindowsCapability -Online | Out-Null
        Log "[OK] $Name installed"
        return $true
    } catch {
        Log "[WARN] $Name install failed: $_"
        return $false
    }
}

# ============================================================
# Step 2: Configure sshd service
# ============================================================
function Configure-SSHD {
    # Ensure sshd service exists and is running
    $sshd = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $sshd) {
        Log "[WARN] sshd service not found, trying to install..."
        & "C:\Windows\System32\OpenSSH\install-sshd.ps1" 2>&1 | Out-Null
        $sshd = Get-Service sshd -ErrorAction SilentlyContinue
    }
    if (-not $sshd) {
        Log "[ERROR] Cannot install sshd service"
        return $false
    }

    # Set startup type to auto
    Set-Service sshd -StartupType Automatic
    Log "[OK] sshd startup set to Automatic"

    # Start if not running
    if ($sshd.Status -ne "Running") {
        Start-Service sshd
        Log "[OK] sshd started"
    } else {
        Log "[OK] sshd already running"
    }

    # Firewall rule
    $fw = netsh advfirewall firewall show rule name="OpenSSH-Server" 2>&1
    if ($fw -match "No rules match") {
        netsh advfirewall firewall add rule name="OpenSSH-Server" dir=in `
            action=allow protocol=TCP localport=22 2>&1 | Out-Null
        Log "[OK] Firewall rule added for port 22"
    } else {
        Log "[OK] Firewall rule already exists"
    }

    return $true
}

# ============================================================
# Step 3: Create directories & deploy key
# ============================================================
function Deploy-TunnelKey {
    if (-not (Test-Path $ScriptDir)) {
        New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
        Log "[OK] Created: $ScriptDir"
    }

    # Write private key via base64 decode (single line, no here-string issues)
    try {
        $keyBytes = [Convert]::FromBase64String("LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCQ0VvMDFVUkVBdFNreExwMjZvVEJuUWpRZStLRW1iMmRrYXVyK0kwdEU1d0FBQUpnTHdRbnhDOEVKCjhRQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQkNFbzAxVVJFQXRTa3hMcDI2b1RCblFqUWUrS0VtYjJka2F1citJMHRFNXcKQUFBRUFhZDNRdzRZc1o4REtuaDlEaDAzNDFHelk2TjZCWFpyL3J3RjNPRkRyOVprSVNqVFZSRVFDMUtURXVuYnFoTUdkQwpOQjc0b1NadloyUnE2djRqUzBUbkFBQUFFblJ2Ym1kc2FXRnVaekUwTFhSMWJtNWxiQUVDQXc9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K")
        [IO.File]::WriteAllBytes($KeyFile, $keyBytes)
        Log "[OK] Key written: $KeyFile ($($keyBytes.Length) bytes)"
    } catch {
        Log "[ERROR] Key write failed: $_"
        return $false
    }

    # Set ACL
    try {
        icacls $KeyFile /reset /q 2>$null
        icacls $KeyFile /inheritance:r /q 2>$null
        $cu = whoami
        icacls $KeyFile /grant "${cu}:(R,W)" /q 2>$null
        icacls $KeyFile /grant "BUILTIN\Administrators:(R)" /q 2>$null
        Log "[OK] Key permissions set"
    } catch {
        Log "[WARN] Permission set failed: $_"
    }

    return $true
}

# ============================================================
# Step 4: Create keepalive script
# ============================================================
function Create-KeepAliveScript {
    $content = @'
#Requires -Version 5.1
param(
    [string]$TU = "__TUNNEL_USER__",
    [string]$TH = "__TUNNEL_HOST__",
    [int]$TP = __TUNNEL_PORT__,
    [string]$KF = "$env:USERPROFILE\scripts\tunnel_id_ed25519"
)
$LogFile = Join-Path $env:USERPROFILE "scripts\tunnel-keepalive.log"
function L { param([string]$M)
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$t $M" | Out-File $LogFile -Encoding UTF8 -Append
}

# Check if tunnel to $TH:22 is active (netstat shows remote:22 ESTABLISHED)
$found = $false
netstat -an | Select-String "$($TH):22\s+ESTABLISHED" | ForEach-Object { $found = $true }
if ($found) {
    L "[OK] Tunnel alive (SSH $($TH):22 ESTABLISHED)"
    exit 0
}

L "[TUNNEL] Dead, reconnecting..."
Start-Process -FilePath "ssh" -ArgumentList @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=`$null",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-o", "ExitOnForwardFailure=yes",
    "-N", "-R", "0.0.0.0:$($TP):localhost:22",
    "$($TU)@$($TH)",
    "-i", "$KF"
) -NoNewWindow -WindowStyle Hidden
L "[TUNNEL] Reconnect initiated (PID: $((Get-Process -Name ssh -ErrorAction SilentlyContinue | Select -Last 1).Id))"
'@

    # Replace placeholders
    $content = $content.Replace("__TUNNEL_USER__", $TunnelUser)
    $content = $content.Replace("__TUNNEL_HOST__", $TunnelHost)
    $content = $content.Replace("__TUNNEL_PORT__", $TunnelPort.ToString())

    $content | Out-File -FilePath $KeepAliveScript -Encoding UTF8
    Log "[OK] Keepalive script: $KeepAliveScript"
}

# ============================================================
# Step 5: Start tunnel & register scheduled task
# ============================================================
function Start-TunnelAndTask {
    # Kill any existing tunnel for these params
    Get-Process -Name ssh -ErrorAction SilentlyContinue | ForEach-Object {
        $cmd = $_.CommandLine
        if ($cmd -match [regex]::Escape("${TunnelUser}@${TunnelHost}") -and
            $cmd -match [regex]::Escape("-R 0.0.0.0:${TunnelPort}")) {
            $_.Kill()
            Log "[TUNNEL] Killed old tunnel process (PID: $($_.Id))"
        }
    }

    # Start tunnel
    $p = Start-Process -FilePath "ssh" -ArgumentList @(
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=`$null",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
        "-N", "-R", "0.0.0.0:${TunnelPort}:localhost:22",
        "${TunnelUser}@${TunnelHost}",
        "-i", $KeyFile
    ) -NoNewWindow -WindowStyle Hidden -PassThru
    Log "[TUNNEL] Started (PID: $($p.Id))"

    # Wait a moment then verify
    Start-Sleep -Seconds 3
    if ($p.HasExited) {
        Log "[WARN] Tunnel process exited immediately (exit code: $($p.ExitCode))"
        Log "[HINT] Run manually to debug:"
        Log "       ssh -v -o StrictHostKeyChecking=no -i $KeyFile ${TunnelUser}@${TunnelHost}"
    } else {
        Log "[OK] Tunnel process running"
    }

    # Register scheduled task
    Log "[..] Registering scheduled task..."
    try {
        # Remove old task if exists
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$KeepAliveScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes 5) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
            -Hidden
        $principal = New-ScheduledTaskPrincipal `
            -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType S4U -RunLevel Limited

        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        Log "[OK] Task registered: $TaskName (every 5min)"
    } catch {
        Log "[ERROR] Task registration failed: $_"
    }
}

# ============================================================
# MAIN
# ============================================================
Write-Banner

Log "=== Setup Starting ==="
Log "ScriptDir: $ScriptDir"
Log "Tunnel: ${TunnelUser}@${TunnelHost}:${TunnelPort}"
Log ""

# Step 1: OpenSSH Client + Server
Log "--- Step 1/5: Install OpenSSH ---"
Install-OpenSSH "OpenSSH.Server*"
Install-OpenSSH "OpenSSH.Client*"
Log ""

# Step 2: Configure sshd
Log "--- Step 2/5: Configure SSHD ---"
Configure-SSHD
Log ""

# Step 3: Deploy key
Log "--- Step 3/5: Deploy Tunnel Key ---"
Deploy-TunnelKey
Log ""

# Step 4: Keepalive script
Log "--- Step 4/5: Keepalive Script ---"
Create-KeepAliveScript
Log ""

# Step 5: Tunnel + task
Log "--- Step 5/5: Start Tunnel & Register Task ---"
Start-TunnelAndTask
Log ""

Log "=== Setup Complete ==="
Log ""
Log "NEXT STEPS:"
Log "  1. Verify tunnel on Mac: ssh -p ${TunnelPort} qcjc@${TunnelHost}"
Log "  2. Password: (qcjc user password)"
Log "  3. Logs: $ScriptDir"
Log "     - Setup: endpoint-setup.log"
Log "     - Keepalive: tunnel-keepalive.log"
Log ""

Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOY COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Tunnel: ${TunnelUser}@${TunnelHost}:${TunnelPort}"
Write-Host "  Access: ssh -p ${TunnelPort} qcjc@${TunnelHost}"
Write-Host "============================================" -ForegroundColor Green
