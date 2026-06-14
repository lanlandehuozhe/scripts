<#
.SYNOPSIS
  Network Diagnostic Tool - Baseline + Monitor
.USAGE
  powershell -File netdiag.ps1 -Baseline    # First run: detect everything
  powershell -File netdiag.ps1 -Monitor     # Every 15min: test speed + log
#>

param([switch]$Baseline, [switch]$Monitor)

$BUCKET_URL = "https://a1-plr-1392076551.cos.ap-chengdu.myqcloud.com"
$BASELINE = "$env:USERPROFILE\.netdiag_baseline"
$LOG = "$env:USERPROFILE\network_monitor.log"
$TEST_FILE = "$env:TEMP\net_test_5mb.bin"
$CSV_LOG = "$env:USERPROFILE\network_monitor.csv"

# ======================== BASELINE ========================
if ($Baseline) {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "  Network Diagnostic - Baseline" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan

    Write-Host "[1/8] Public IP..."
    $publicIP = "FAIL"
    try { $publicIP = (Invoke-WebRequest -Uri "https://ip.sb" -UseBasicParsing -TimeoutSec 5).Content.Trim() } catch {}
    if ($publicIP -eq "FAIL") { try { $publicIP = (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing -TimeoutSec 5).Content.Trim() } catch {} }

    Write-Host "[2/8] ISP..."
    $isp = "FAIL"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $org = (Invoke-WebRequest -Uri "https://ipinfo.io/$publicIP/org" -UseBasicParsing -TimeoutSec 5).Content.Trim()
        if ($org -match "AS(\d+)") {
            $asn = $matches[1]
            switch ($asn) {
                "4837"  { $isp = "China-Unicom AS$asn" }
                "4134"  { $isp = "China-Telecom AS$asn" }
                "9808"  { $isp = "China-Mobile AS$asn" }
                "4808"  { $isp = "China-Unicom AS$asn" }
                "4847"  { $isp = "China-Telecom AS$asn" }
                default { $isp = "$org" }
            }
        } else { $isp = $org }
    } catch {}

    Write-Host "[3/8] Gateway..."
    $gw = "FAIL"
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if ($route) { $gw = ($route | Select-Object -First 1).NextHop.IPAddressToString }
    } catch {}
    if ($gw -eq "FAIL") {
        $r = route print -4 | Select-String "0.0.0.0"
        if ($r) { $gw = ($r[0] -split '\s+')[2] }
    }

    Write-Host "[4/8] Local IP..."
    $localIP = "FAIL"
    try { 
        $adapter = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if ($adapter) {
            $localIP = (Get-NetIPAddress -InterfaceIndex $adapter[0].InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        }
    } catch {}
    if (-not $localIP -or $localIP -eq "FAIL") {
        $localIP = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway }).IPAddress[0]
    }

    Write-Host "[5/8] DNS..."
    $dns = "FAIL"
    try {
        $dnsList = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses -and $_.InterfaceAlias }).ServerAddresses
        $dns = ($dnsList | Select-Object -First 2) -join ", "
    } catch {}

    Write-Host "[6/8] Generating test file (5MB)..."
    if (-not (Test-Path $TEST_FILE)) {
        $f = [System.IO.File]::Create($TEST_FILE)
        $f.SetLength(5*1024*1024)
        $f.Close()
    }

    Write-Host "[7/8] Upload speed test (5MB to COS)..."
    $upMbps = "FAIL"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rand = "test_$(Get-Random)"
        $url = "$BUCKET_URL/$rand"
        $wc = New-Object System.Net.WebClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc.UploadFile($url, $TEST_FILE) | Out-Null
        $sw.Stop()
        $upSecs = $sw.Elapsed.TotalSeconds
        $upMbps = "{0:N1}" -f (40.0 / $upSecs)
    } catch { Write-Host "    [upload error] $_" }

    Write-Host "[8/8] Latency test..."
    $pingMs = "FAIL"
    $pingOut = ping -n 4 223.5.5.5 2>$null | Out-String
    if ($pingOut -match "平均\s*=\s*(\d+)|Average\s*=\s*(\d+)") {
        $pingMs = $matches[1]
        if (-not $pingMs) { $pingMs = $matches[2] }
    }

    # Save baseline
@"
TIME=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
PUBLIC_IP=$publicIP
ISP=$isp
GATEWAY=$gw
LOCAL_IP=$localIP
DNS=$dns
UPLOAD_MBPS=$upMbps
PING_MS=$pingMs
BW_ESTIMATE=${upMbps} Mbps
"@ | Out-File -FilePath $BASELINE -Encoding ASCII

    # Init CSV header
    "Timestamp,Upload_Mbps,Latency_ms,PacketLoss_Pct" | Out-File -FilePath $CSV_LOG -Encoding ASCII

    Clear-Host
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "  Network Baseline Complete" -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Time:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "  Public:     $publicIP"
    Write-Host "  ISP:        $isp"
    Write-Host "  Gateway:    $gw"
    Write-Host "  Local IP:   $localIP"
    Write-Host "  Upload:     $upMbps Mbps"
    Write-Host "  Latency:    $pingMs ms"
    Write-Host "-------------------------------------------"
    Write-Host "  CSV log:    $CSV_LOG"
    Write-Host "  Schedule:   every 15min via task"
    Write-Host "==========================================="
}

# ======================== MONITOR ========================
if ($Monitor) {
    if (-not (Test-Path $BASELINE)) {
        Write-Host "[ERROR] Run -Baseline first!"
        exit 1
    }

    # Ensure test file exists
    if (-not (Test-Path $TEST_FILE)) {
        $f = [System.IO.File]::Create($TEST_FILE)
        $f.SetLength(5*1024*1024)
        $f.Close()
    }

    # Upload test
    $upMbps = 0
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rand = "test_$(Get-Random)"
        $url = "$BUCKET_URL/$rand"
        $wc = New-Object System.Net.WebClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc.UploadFile($url, $TEST_FILE) | Out-Null
        $sw.Stop()
        $upMbps = [Math]::Round(40.0 / $sw.Elapsed.TotalSeconds, 1)
    } catch {}

    # Latency + packet loss
    $pingMs = 9999
    $loss = 100
    $pingOut = ping -n 4 223.5.5.5 2>$null | Out-String
    if ($pingOut -match "平均\s*=\s*(\d+)|Average\s*=\s*(\d+)") {
        $pingMs = $matches[1]
        if (-not $pingMs) { $pingMs = $matches[2] }
    }
    if ($pingOut -match "(\d+)%") {
        $loss = $matches[1]
    }

    # CSV append
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts,$upMbps,$pingMs,$loss" | Out-File -FilePath $CSV_LOG -Encoding ASCII -Append

    # Alert
    if ($upMbps -lt 1) { Write-Host "[ALERT] Upload speed < 1 Mbps at $ts" }
    if ($loss -gt 0) { Write-Host "[ALERT] Packet loss: ${loss}% at $ts" }
}
