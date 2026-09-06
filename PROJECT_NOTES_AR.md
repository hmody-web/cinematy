# قرارات المشروع

- الاسم: Cinematy / سينماتي
- Bundle ID: `com.cinematy.app`
- اللون الأساسي: `rgb(13, 0, 0)`
- اللغة الوحيدة حالياً: العربية RTL
- المصدر: Cinemana (`cinemana.shabakaty.cc`)
- الواجهة منفصلة بالكامل عن API حتى يمكن تعديل المصدر لاحقاً.
- الصور: Memory + Disk cache عبر `cached_network_image`.
- JSON API: Memory + Disk TTL cache مخصص.
- المشغل: `media_kit` مع واجهة عربية مخصصة وجودات وترجمة واستكمال المشاهدة.
- البار السفلي: عائم/زجاجي/Blur/Animated ويعمل على iOS وAndroid.

## Endpoints المضمنة
- AdvancedSearch
- AvailableSearchYears
- videoGroups/lang/{lang}
- banner/level/{level}
- categories
- collectionsId
- getCollection/collectionID/{id}
- collectionVideos/collectionID/{id}
- newlyVideosItems/level/{level}
- videoListPagination/groupID/{id}
- allVideoInfo/id/{id}
- videoSeason/id/{id}
- transcoddedFiles/id/{id}
- translationFiles/id/{id}
- staff/actorID/{id}
- Recommendation API

طبقة `CinemanaApi` تستخدم parsing مرن لأسماء الحقول المختلفة حتى تتحمل اختلافات بسيطة في استجابة المصدر.
