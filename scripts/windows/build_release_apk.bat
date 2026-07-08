@echo off
setlocal EnableExtensions
title SmartDolphinVPN Release APK

REM Always build from Flutter project root (pubspec.yaml next to this file).
REM If you copied this script to Desktop, we still cd to the repo below.
set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

if not exist "pubspec.yaml" (
  cd /d "Z:\SmartDolphinVPN\SmartDolphinVPNAndroid"
)
if not exist "pubspec.yaml" (
  echo [ERROR] pubspec.yaml not found. Put this .bat inside SmartDolphinVPNAndroid folder, or fix PROJECT path in this script.
  pause
  exit /b 1
)

echo ============================================================
echo   Close Cursor before build to reduce OOM. Building in:
echo   %CD%
echo ============================================================
echo.

REM Prefer full path so "flutter" is never mangled by encoding/PATH.
set "FLUTTER_EXE=D:\Development\flutter\bin\flutter.bat"
if exist "%FLUTTER_EXE%" goto have_flutter
where flutter >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Flutter not found. Install to D:\Development\flutter or add flutter to PATH.
  pause
  exit /b 1
)
set "FLUTTER_EXE=flutter"

:have_flutter
echo Using: %FLUTTER_EXE%
echo.

call "%FLUTTER_EXE%" build apk --release
set ERR=%ERRORLEVEL%

echo.
if %ERR% equ 0 (
  echo OK:
  echo   %CD%\build\app\outputs\flutter-apk\app-release.apk
  if exist "build\app\outputs\flutter-apk\app-release.apk" (
    dir "build\app\outputs\flutter-apk\app-release.apk"
  )
) else (
  echo Build failed, exit code: %ERR%
)
echo.
pause
exit /b %ERR%
