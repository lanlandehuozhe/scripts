@echo off
chcp 936 >nul
echo Installing COS bandwidth monitor...
echo.

REM Download the test script
curl -o %userprofile%\cos-upload-test.bat -s https://a1-temp-1392076551.cos.ap-chengdu.myqcloud.com/tools/cos-upload-test.bat
if %ERRORLEVEL% NEQ 0 (
    echo Download failed!
    pause
    exit /b 1
)
echo [1/2] Script downloaded to %%userprofile%%\cos-upload-test.bat

REM Add scheduled task (every 15 min)
schtasks /create /tn "COS Bandwidth Monitor" /tr "cmd.exe /c \"%userprofile%\cos-upload-test.bat\"" /sc minute /mo 15 /f >nul 2>&1
echo [2/2] Task added: COS Bandwidth Monitor

echo.
echo Done! Check results tomorrow:
echo   type %%userprofile%%\cos_speed_test.log
pause
