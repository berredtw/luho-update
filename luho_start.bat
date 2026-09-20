@echo off
chcp 950 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"
title 陸吼天堂 自動更新啟動器 v1.6 (2026-09-20)

rem ===== 必須放在遊戲資料夾 =====
if not exist "Lin.bin" (
    echo [錯誤] 請把本檔放進天堂遊戲資料夾（有 Lin.bin 的那層）再執行。
    pause
    exit /b 1
)

set "BASEURL=https://berredtw.github.io/luho-update"
set "MANIFEST=%TEMP%\luho_manifest.txt"
set "PATCHLIST=%TEMP%\luho_patches.txt"
set "UPDATED=0"
set "CHECKONLY=0"
if /i "%~1"=="/checkonly" set "CHECKONLY=1"

rem ===== 啟動器自我更新：換掉自己後自動重開（失敗就照常往下走）=====
if exist "luho_start_new.bat" (
    fc /b "luho_start_new.bat" "%~f0" >nul 2>&1
    if errorlevel 1 (
        echo [更新] 啟動器有新版本，套用後自動重新開啟...
        copy /y "luho_start_new.bat" "%~f0.tmp" >nul 2>&1
        if exist "%~f0.tmp" (
            start "" /min cmd /c "ping -n 3 127.0.0.1 >nul & move /y ""%~f0.tmp"" ""%~f0"" >nul 2>&1 & start """" ""%~f0"" %1"
            exit /b 0
        )
    )
)

rem ===== 遊戲開著檔案會被鎖，略過更新直接開 =====
tasklist /fi "imagename eq Login.exe" 2>nul | find /i "Login.exe" >nul
if not errorlevel 1 (
    echo [提示] 偵測到遊戲執行中，本次略過更新。
    goto launch
)

echo 檢查更新中...
del "%MANIFEST%" >nul 2>&1
curl -s -f -L -m 15 "%BASEURL%/manifest.txt" -o "%MANIFEST%"
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
goto patches

rem ===== 單檔檢查：指紋不同才下載，下載完再驗一次 =====
:checkfile
set "FNAME=%~1"
set "RMD5=%~2"
set "FSPATH=%FNAME:/=\%"
rem 演算法自動偵測：清單指紋 64 字元=SHA256、32 字元=MD5（新舊清單通吃，防 v1.1 事件重演）
set "ALGO=SHA256"
if "%RMD5:~32,1%"=="" set "ALGO=MD5"
set "LMD5="
if exist "%FSPATH%" (
    for /f "skip=1 delims=" %%H in ('certutil -hashfile "%FSPATH%" %ALGO% 2^>nul') do (
        if not defined LMD5 set "LMD5=%%H"
    )
    set "LMD5=!LMD5: =!"
)
if /i "!LMD5!"=="%RMD5%" goto :eof
echo [更新] %FNAME% 下載中（請稍候）...
for %%D in ("%FSPATH%") do set "FDIR=%%~dpD"
if not exist "!FDIR!" mkdir "!FDIR!" >nul 2>&1
curl -s -f -L -m 600 "%BASEURL%/%FNAME%" -o "%FSPATH%.new"
if errorlevel 1 goto dlfail
if not exist "%FSPATH%.new" goto dlfail
set "NMD5="
for /f "skip=1 delims=" %%H in ('certutil -hashfile "%FSPATH%.new" %ALGO% 2^>nul') do (
    if not defined NMD5 set "NMD5=%%H"
)
set "NMD5=!NMD5: =!"
if /i not "!NMD5!"=="%RMD5%" goto dlfail
move /y "%FSPATH%.new" "%FSPATH%" >nul
echo [更新] %FNAME% 完成。
set "UPDATED=1"
goto :eof

:dlfail
echo [失敗] %FNAME% 下載失敗，本次先用舊檔進遊戲（不影響遊玩）。
del "%FSPATH%.new" >nul 2>&1
goto :eof

rem ===== 圖檔補丁：只套沒套過的，失敗一律不擋遊戲 =====
:patches
if not exist "applied_patches.txt" type nul > "applied_patches.txt"
del "%PATCHLIST%" >nul 2>&1
curl -s -f -L -m 15 "%BASEURL%/patches.txt" -o "%PATCHLIST%" 2>nul
if errorlevel 1 goto launch
if not exist "%PATCHLIST%" goto launch
for /f "usebackq tokens=1,2 delims=|" %%A in ("%PATCHLIST%") do (
    call :checkpatch "%%A" "%%B"
)
goto launch

:checkpatch
set "PNAME=%~1"
set "PHASH=%~2"
if "%PNAME%"=="" goto :eof
findstr /x /c:"%PNAME%" "applied_patches.txt" >nul 2>&1
if not errorlevel 1 goto :eof
if not exist "_patch" mkdir "_patch" >nul 2>&1
rem --- v1.6 快取：本機已有正確的補丁檔就不重複下載（省流量、失敗重試也不再重抓）---
set "NEEDDL=1"
if exist "_patch\%PNAME%.dat" (
    set "CHASH="
    for /f "skip=1 delims=" %%H in ('certutil -hashfile "_patch\%PNAME%.dat" SHA256 2^>nul') do (
        if not defined CHASH set "CHASH=%%H"
    )
    set "CHASH=!CHASH: =!"
    if /i "!CHASH!"=="%PHASH%" set "NEEDDL=0"
)
if "!NEEDDL!"=="1" (
    echo [圖檔] 發現新圖檔補丁 %PNAME%，下載中...
    curl -s -f -L -m 600 "%BASEURL%/patches/%PNAME%.dat" -o "_patch\%PNAME%.dat"
    if errorlevel 1 goto patchfail
    set "DHASH="
    for /f "skip=1 delims=" %%H in ('certutil -hashfile "_patch\%PNAME%.dat" SHA256 2^>nul') do (
        if not defined DHASH set "DHASH=%%H"
    )
    set "DHASH=!DHASH: =!"
    if /i not "!DHASH!"=="%PHASH%" goto patchfail
) else (
    echo [圖檔] 套用先前已下載的補丁 %PNAME%...
)
curl -s -f -L -m 60 "%BASEURL%/patches/%PNAME%.manifest" -o "_patch\%PNAME%.manifest"
if errorlevel 1 goto patchfail
curl -s -f -L -m 60 "%BASEURL%/patches/apply_patch.ps1" -o "_patch\apply_patch.ps1"
if errorlevel 1 goto patchfail
powershell -NoProfile -ExecutionPolicy Bypass -File "_patch\apply_patch.ps1" -GameDir "%CD%" -PatchDir "%CD%\_patch" -PatchName "%PNAME%" -LogFile "_patch\%PNAME%.log"
if errorlevel 1 goto patchnotapply
echo %PNAME%>>"applied_patches.txt"
echo [圖檔] %PNAME% 套用完成。
goto :eof

:patchnotapply
echo [提示] 圖檔補丁 %PNAME% 這次沒套用成功。
echo        若你還沒安裝過「紋樣大圖包」，請先到更新站下載安裝一次，之後就會自動套用。
goto :eof

:patchfail
echo [提示] 圖檔補丁 %PNAME% 下載失敗，不影響進遊戲（下次啟動會再試）。
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
