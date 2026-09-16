@echo off
setlocal
cd /d "%~dp0"
echo [1/3] Cleaning...
call flutter clean || exit /b 1
echo [2/3] Packages...
call flutter pub get || exit /b 1
echo [3/3] Building Cinematy TV Lite...
call flutter build apk --release || exit /b 1
echo.
echo APK READY:
echo %CD%\build\app\outputs\flutter-apk\app-release.apk
endlocal
