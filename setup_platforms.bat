@echo off
setlocal
flutter create --platforms=android,ios --project-name cinematy --org com.cinematy .
for /r android %%f in (*.kt *.java *.gradle *.kts) do powershell -NoProfile -Command "(Get-Content -Raw '%%f') -replace 'com\.cinematy\.cinematy','com.cinematy.app' | Set-Content -NoNewline '%%f'"
for /r ios %%f in (*.pbxproj *.plist) do powershell -NoProfile -Command "(Get-Content -Raw '%%f') -replace 'com\.cinematy\.cinematy','com.cinematy.app' | Set-Content -NoNewline '%%f'"
flutter pub get
dart run flutter_launcher_icons
endlocal
