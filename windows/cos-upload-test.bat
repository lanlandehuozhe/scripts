@echo off
chcp 936 >nul

set BUCKET_URL=https://a1-plr-1392076551.cos.ap-chengdu.myqcloud.com
set LOG_FILE=%userprofile%\cos_speed_test.log
set TEST_FILE=%temp%\cos_speed_test_5mb.bin

echo ================================
echo   COS Bandwidth Monitor
echo ================================

echo [1/3] Detecting network...
curl -s ip.sb > %temp%\cos_public_ip.txt 2>nul
set /p PUBLIC_IP=<%temp%\cos_public_ip.txt
if "%PUBLIC_IP%"=="" set PUBLIC_IP=unknown
del %temp%\cos_public_ip.txt 2>nul

REM Get ISP
curl -s "https://ipinfo.io/%PUBLIC_IP%/org" > %temp%\cos_isp.txt 2>nul
set /p ISP=<%temp%\cos_isp.txt
if "%ISP%"=="" set ISP=unknown
del %temp%\cos_isp.txt 2>nul

echo   Public IP: %PUBLIC_IP%
echo   ISP:       %ISP%

echo [2/3] Preparing test file...
if not exist "%TEST_FILE%" (
    powershell -Command "$f=[System.IO.File]::Create('%TEST_FILE%');$f.SetLength(5*1024*1024);$f.Close()" >nul
)
echo   Test file: 5MB

echo [3/3] Testing upload speed...
set RAND_NAME=test_%RANDOM%
for /f "tokens=*" %%t in ('powershell -Command "$u='%BUCKET_URL%/%RAND_NAME%';$f=[System.Diagnostics.Stopwatch]::StartNew();(New-Object System.Net.WebClient).UploadFile($u,'%TEST_FILE%');$f.Stop();'{0:0.0}' -f $f.Elapsed.TotalSeconds"') do set DURATION=%%t

REM calculate Mbps: 8*5/duration
for /f "tokens=*" %%s in ('powershell -Command "'{0:0.00}' -f (40/%DURATION%)"') do set MBPS=%%s

echo %DATE% %TIME% %PUBLIC_IP% %ISP% %DURATION%s %MBPS%Mbps >> "%LOG_FILE%"

echo ----------------------------
echo   Time:    %DATE% %TIME%
echo   IP:      %PUBLIC_IP%
echo   ISP:     %ISP%
echo   Speed:   %MBPS% Mbps (5MB to COS)
echo ----------------------------
