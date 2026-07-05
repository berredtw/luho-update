@echo off
chcp 950 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"
title 陸吼天堂 自動更新啟動器 v1.1 (2026-07-05)

rem ===== 必須放在遊戲資料夾 =====
if not exist "Lin.bin" (
    echo [錯誤] 請把本檔放進天堂遊戲資料夾（有 Lin.bin 的那層）再執行。
    pause
    exit /b 1
)

set "BASEURL=https://berredtw.github.io/luho-update"
set "MANIFEST=%TEMP%\luho_manifest.txt"
set "UPDATED=0"
set "CHECKONLY=0"
if /i "%~1"=="/checkonly" set "CHECKONLY=1"

rem ===== 遊戲開著檔案會被鎖，略過更新直接開 =====
tasklist /fi "imagename eq Login.exe" 2>nul | find /i "Login.exe" >nul
if not errorlevel 1 (
    echo [提示] 偵測到遊戲執行中，本次略過更新。
    goto launch
)

echo 檢查更新中...
del "%MANIFEST%" >nul 2>&1
curl -s -L -m 15 "%BASEURL%/manifest.txt" -o "%MANIFEST%"
if errorlevel 1 goto nonet
if not exist "%MANIFEST%" goto nonet
findstr /r "." "%MANIFEST%" >nul || goto nonet

for /f "usebackq tokens=1,2 delims=|" %%A in ("%MANIFEST%") do (
    call :checkfile "%%A" "%%B"
)
if "%UPDATED%"=="1" (
    echo.
    echo [完成] 更新安裝完畢！
    timeout /t 2 >nul
) else (
    echo 已是最新版本。
)
goto launch

rem ===== 單檔檢查：md5 不同才下載，下載完再驗一次 =====
:checkfile
set "FNAME=%~1"
set "RMD5=%~2"
set "LMD5="
if exist "%FNAME%" (
    for /f "skip=1 delims=" %%H in ('certutil -hashfile "%FNAME%" MD5 2^>nul') do (
        if not defined LMD5 set "LMD5=%%H"
    )
    set "LMD5=!LMD5: =!"
)
if /i "!LMD5!"=="%RMD5%" goto :eof
echo [更新] %FNAME% 下載中（請稍候）...
curl -s -L -m 600 "%BASEURL%/%FNAME%" -o "%FNAME%.new"
if errorlevel 1 goto dlfail
if not exist "%FNAME%.new" goto dlfail
set "NMD5="
for /f "skip=1 delims=" %%H in ('certutil -hashfile "%FNAME%.new" MD5 2^>nul') do (
    if not defined NMD5 set "NMD5=%%H"
)
set "NMD5=!NMD5: =!"
if /i not "!NMD5!"=="%RMD5%" goto dlfail
move /y "%FNAME%.new" "%FNAME%" >nul
echo [更新] %FNAME% 完成。
set "UPDATED=1"
goto :eof

:dlfail
echo [失敗] %FNAME% 下載失敗，本次先用舊檔進遊戲（不影響遊玩）。
del "%FNAME%.new" >nul 2>&1
goto :eof

:nonet
echo [提示] 無法連線更新站，直接開遊戲。

:launch
if "%CHECKONLY%"=="1" (
    echo （檢查模式：不啟動遊戲）
    exit /b 0
)
start "" "Login.exe"
exit /b 0
