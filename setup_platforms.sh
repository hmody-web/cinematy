#!/usr/bin/env bash
set -e
flutter create --platforms=android,ios --project-name cinematy --org com.cinematy .
# flutter create ينتج com.cinematy.cinematy، نبدله بالمعرف المطلوب.
find android ios -type f \( -name '*.kt' -o -name '*.java' -o -name '*.gradle' -o -name '*.kts' -o -name '*.pbxproj' -o -name '*.plist' \) -print0 | xargs -0 sed -i.bak 's/com\.cinematy\.cinematy/com.cinematy.app/g' || true
find android ios -name '*.bak' -delete || true
flutter pub get
dart run flutter_launcher_icons
