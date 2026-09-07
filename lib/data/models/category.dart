import '../../core/utils/json_utils.dart';
import 'media_item.dart';

/// تصنيف Cinemana الحقيقي القادم من /api/android/categories.
///
/// تطبيق Cinemana الأصلي لا يعتمد عنوان التصنيف وحده عند فتحه، وإنما يحتفظ
/// برقم التصنيف categoryNb الموجود داخل langArray ثم يستخدمه مع
/// /api/android/video/V/2. لذلك نحتفظ بهذه البيانات صراحةً هنا.
class MediaCategory {
  const MediaCategory({
    required this.id,
    required this.title,
    this.count = 0,
    this.coverUrl = '',
    this.languageId = '',
    this.order = 0,
  });

  /// هو نفسه categoryNb في Cinemana.
  final String id;
  final String title;
  final int count;

  /// صورة التصنيف المباشرة القادمة من Category.videoInfo.
  final String coverUrl;

  /// langNb الافتراضي إن وفره المصدر. يترك فارغاً لعرض كل اللغات.
  final String languageId;

  /// porder من المصدر للمحافظة على ترتيب Cinemana.
  final int order;

  factory MediaCategory.fromJson(Map<String, dynamic> json) => MediaCategory(
        id: JsonUtils.string(
          json,
          ['categoryNb', 'catNb', 'nb', 'id', 'category_id'],
        ),
        title: JsonUtils.string(
          json,
          ['arTitle', 'lang_ar_title', 'ar_title', 'title', 'name', 'enTitle'],
          fallback: 'تصنيف',
        ),
        count: JsonUtils.integer(json, ['count', 'itemsCount']),
        coverUrl: normalizeMediaUrl(
          JsonUtils.string(
            json,
            [
              'imgMediumThumbObjUrl',
              'imgThumbObjUrl',
              'imgObjUrl',
              'imgMediumThumb',
              'imgThumb',
              'image',
              'cover',
            ],
          ),
        ),
        languageId: JsonUtils.string(json, ['langNb', 'languageNb']),
        order: JsonUtils.integer(json, ['porder', 'order']),
      );
}
