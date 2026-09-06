import '../../core/utils/json_utils.dart';

class MediaCategory {
  const MediaCategory({required this.id, required this.title, this.count = 0});
  final String id;
  final String title;
  final int count;

  factory MediaCategory.fromJson(Map<String, dynamic> json) => MediaCategory(
    id: JsonUtils.string(json, ['catNb', 'categoryNb', 'id', 'category_id']),
    title: JsonUtils.string(json, ['lang_ar_title', 'ar_title', 'title', 'name'], fallback: 'تصنيف'),
    count: JsonUtils.integer(json, ['count', 'itemsCount']),
  );
}
