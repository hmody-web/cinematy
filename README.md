# Cinematy — سينماتي

مشروع Flutter عربي بالكامل (RTL) باسم **cinematy** وبـ Bundle ID: `com.cinematy.app`.

## التصميم
- اللون الأساسي للخلفية: `rgb(13, 0, 0)` / `#0D0000`.
- شريط تنقل سفلي عائم زجاجي مع Blur وحركة اختيار ناعمة.
- واجهة سينمائية خفيفة تعتمد Slivers وLazy lists.
- صور شبكية مع Disk/Memory cache.
- حفظ المفضلة وسجل المشاهدة وآخر موضع تشغيل محلياً.
- مشغل فيديو مخصص يدعم HLS/MP4 والجودات والترجمة.

## مصدر البيانات
المصدر مضبوط في:
`lib/core/config/app_config.dart`

الافتراضي:
`https://cinemana.shabakaty.cc`

الطبقة الشبكية معزولة في `CinemanaApi` حتى يمكن تعديل المسارات لاحقاً بدون لمس الواجهة.

> ملاحظة: بعض واجهات المصدر قد تعتمد معاملات/صلاحيات تتغير مع الوقت. المشروع لا يتجاوز تسجيل الدخول أو DRM؛ استخدم فقط الـ endpoints والروابط المسموح لك الوصول إليها.

## تشغيل المشروع
```bash
flutter pub get
flutter run
```

إذا أردت إعادة توليد أيقونات التطبيق من الصورة المرفقة:
```bash
dart run flutter_launcher_icons
```

## إنشاء/إصلاح مجلدات iOS وAndroid
إذا كانت نسخة Flutter لديك أحدث من ملفات المنصات الموجودة، يمكنك تشغيل:

Windows:
```bat
setup_platforms.bat
```

macOS/Linux:
```bash
bash setup_platforms.sh
```

السكريبت يحافظ على `lib` و`assets` ثم يعيد توليد ملفات المنصات بالمعرف `com.cinematy.app`.
