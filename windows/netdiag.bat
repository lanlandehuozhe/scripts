@echo off
chcp 936 >nul
setlocal enabledelayedexpansion
title NetDiag

set BUCKET_URL=https://a1-plr-1392076551.cos.ap-chengdu.myqcloud.com
set BASELINE=%userprofile%\.netdiag_baseline
set LOG=%userprofile%\network_monitor.log
set TEST_FILE=%temp%\net_test_5mb.bin
set RAND_NAME=test_%RANDOM%

if "%1"=="/baseline" goto baseline
if "%1"=="/monitor"  goto monitor
goto help

REM ==================== BASELINE ====================
:baseline
cls
echo ===========================================
echo   Network Diagnostic - Baseline
echo ===========================================

echo [1/8] Public IP...
for /f %%i in ('curl -s ip.sb --connect-timeout 5 2^>nul') do set PUBLIC_IP=%%i
if "!PUBLIC_IP!"=="" for /f %%i in ('curl -s ifconfig.me --connect-timeout 5 2^>nul') do set PUBLIC_IP=%%i
if "!PUBLIC_IP!"=="" set PUBLIC_IP=FAIL

echo [2/8] ISP...
for /f %%i in ('curl -s "https://ipinfo.io/!PUBLIC_IP!/org" --connect-timeout 5 2^>nul') do set ISP=%%i
if "!ISP!"=="" for /f %%i in ('curl -s "http://ip.taobao.com/service/getIpInfo.php?ip=!PUBLIC_IP!" --connect-timeout 5 2^>nul ^| find "isp"') do set ISP=%%i
if "!ISP!"=="" set ISP=FAIL

echo [3/8] Gateway...
for /f "tokens=3" %%g in ('route print -4 ^| findstr "0.0.0.0" ^| findstr /V "224\."') do set GW=%%g
if "!GW!"=="" set GW=FAIL

echo [4/8] Local IP...
for /f "tokens=3 delims=: " %%i in ('ipconfig ^| findstr /C:"IPv4" ^| findstr /V "169\."') do if "!LOCAL_IP!"=="" set LOCAL_IP=%%i
if "!LOCAL_IP!"=="" for /f "tokens=3 delims=: " %%i in ('ipconfig ^| findstr /C:"IP Address"') do if "!LOCAL_IP!"=="" set LOCAL_IP=%%i
if "!LOCAL_IP!"=="" set LOCAL_IP=FAIL

echo [5/8] DNS...
for /f "tokens=2 delims=:" %%i in ('ipconfig /all ^| findstr "DNS Servers" ^| findstr /V ":"') do if "!DNS!"=="" set DNS=%%i
if "!DNS!"=="" set DNS=FAIL

echo [6/8] Generating test file (5MB)...
if not exist "%TEST_FILE%" (
    powershell -Command "$f=[System.IO.File]::Create('%TEST_FILE%');$f.SetLength(5*1024*1024);$f.Close()" >nul
)

echo [7/8] Upload speed test (5MB to COS)...
for /f %%t in ('powershell -Command "$u='%BUCKET_URL%/%RAND_NAME%';$f=[System.Diagnostics.Stopwatch]::StartNew();(New-Object System.Net.WebClient).UploadFile($u,'%TEST_FILE%');$f.Stop();'{0:0.0}' -f $f.Elapsed.TotalSeconds"') do set UPLOAD_S=%%t
for /f %%s in ('powershell -Command "'{0:0.0}' -f (40/!UPLOAD_S!)"') do set UPLOAD_MBPS=%%s

echo [8/8] Latency test...
for /f "tokens=5 delims==<>ms " %%i in ('ping -n 4 223.5.5.5 ^| findstr /C:"="') do set PING_MS=%%i
if "!PING_MS!"=="" set PING_MS=FAIL

REM Save baseline
(
echo TIME=%DATE% %TIME%
echo PUBLIC_IP=!PUBLIC_IP!
echo ISP=!ISP!
echo GATEWAY=!GW!
echo LOCAL_IP=!LOCAL_IP!
echo DNS=!DNS!
echo UPLOAD_MBPS=!UPLOAD_MBPS!
echo PING_MS=!PING_MS!
echo BW_ESTIMATE=!UPLOAD_MBPS! Mbps
) > "%BASELINE%"

REM Init log CSV
echo Timestamp,Upload_Mbps,Latency_ms,PacketLoss_Pct > "%LOG%"

cls
echo ===========================================
echo   Network Baseline Complete
echo ===========================================
echo   Time:       %DATE% %TIME%
echo   Public:     !PUBLIC_IP!
echo   ISP:        !ISP!
echo   Gateway:    !GW!
echo   Local IP:   !LOCAL_IP!
echo   Upload:     !UPLOAD_MBPS! Mbps
echo   Latency:    !PING_MS! ms
echo -------------------------------------------
echo   Log: %LOG%
echo   Schedule: every 15min via task
echo ===========================================
goto end

REM ==================== MONITOR ====================
:monitor
if not exist "%BASELINE%" (
    echo [ERROR] Run /baseline first!
    exit /b 1
)

REM Test upload
if not exist "%TEST_FILE%" (
    powershell -Command "$f=[System.IO.File]::Create('%TEST_FILE%');$f.SetLength(5*1024*1024);$f.Close()" >nul
)
set R2=test_%RANDOM%
for /f %%t in ('powershell -Command "$u='%BUCKET_URL%/%R2%';$f=[System.Diagnostics.Stopwatch]::StartNew();(New-Object System.Net.WebClient).UploadFile($u,'%TEST_FILE%');$f.Stop();'{0:0.0}' -f $f.Elapsed.TotalSeconds"') do set UP_S=%%t
for /f %%s in ('powershell -Command "'{0:0.0}' -f (40/!UP_S!)"') do set UP_MBPS=%%s

REM Ping + loss
for /f "tokens=5 delims==<>ms " %%i in ('ping -n 4 223.5.5.5 ^| findstr /C:"="') do set PING_MSV=%%i
if "!PING_MSV!"=="" set PING_MSV=9999
for /f "tokens=6" %%i in ('ping -n 10 223.5.5.5 ^| findstr "丢失"') do set LOSS=%%i
if "!LOSS!"=="" set LOSS=100

REM Log
echo %DATE% %TIME%,!UP_MBPS!,!PING_MSV!,!LOSS! >> "%LOG%"

REM Alert
for /f %%s in ('powershell -Command "'{0:0}' -f (40/!UP_S!)"') do set INT=%%s
if !INT! LSS 1 echo [ALERT] Upload speed ^< 1 Mbps at %DATE% %TIME% >> "%LOG%"
if not "!LOSS!"=="0%" echo [ALERT] Packet loss !LOSS! at %DATE% %TIME% >> "%LOG%"

goto end

REM ==================== HELP ====================
:help
cls
echo.
echo  Network Diagnostic Tool
echo ==========================
echo.
echo  First run (detect everything):
echo    netdiag /baseline
echo.
echo  Scheduled monitor:
echo    netdiag /monitor
echo.
echo  Setup scheduled task once:
echo    schtasks /create /tn "NetMonitor" /tr "cmd /c %%userprofile%%\netdiag.bat /monitor" /sc minute /mo 15 /f
echo.
echo  View logs:
echo    type %%userprofile%%\network_monitor.log
echo.
echo  View baseline:
echo    type %%userprofile%%\.netdiag_baseline
echo.
:end
