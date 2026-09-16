@echo off
setlocal
cd /d "%~dp0"
call flutter clean || exit /b 1
call flutter pub get || exit /b 1
call flutter build apk --release --target-platform android-arm64 || exit /b 1
echo.
echo APK READY:
echo %CD%\build\app\outputs\flutter-apk\app-release.apk
endlocal
