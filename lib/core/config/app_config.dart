class AppConfig {
  AppConfig._();

  static const appName = 'سينماتي';
  static const bundleId = 'com.cinematy.app';

  /// المصدر الوحيد حالياً. لاحقاً يمكن استبداله بـ Remote Config بدون تعديل الواجهة.
  static const baseUrl = 'https://cinemana.shabakaty.cc';
  static const recommendationBaseUrl = 'https://recommend.shabakaty.cc';

  static const language = 'ar';
  static const requestTimeout = Duration(seconds: 15);
  static const apiCacheTtl = Duration(minutes: 8);
  static const detailsCacheTtl = Duration(minutes: 20);
}

class CinemanaRoutes {
  CinemanaRoutes._();

  static const advancedSearch = '/api/android/AdvancedSearch';
  static const availableYears = '/api/android/AvailableSearchYears';
  static const categories = '/api/android/categories';
  static const category = '/api/android/category';
  static const collections = '/api/android/collectionsId';
  static const userInfo = '/api/info/userInfo';

  static String videoGroups(String lang) => '/api/android/videoGroups/lang/$lang';
  static String banner(int level) => '/api/android/banner/level/$level';
  static String collection(String id) => '/api/android/getCollection/collectionID/$id';
  static String collectionVideos(String id) => '/api/android/collectionVideos/collectionID/$id';
  static String newlyVideos(int level) => '/api/android/newlyVideosItems/level/$level';
  static String videoInfo(String id) => '/api/android/allVideoInfo/id/$id';
  static String seasons(String id) => '/api/android/videoSeason/id/$id';
  static String transcodes(String id) => '/api/android/transcoddedFiles/id/$id';
  static String translations(String id) => '/api/android/translationFiles/id/$id';
  static String staff(String id) => '/api/android/staff/actorID/$id';
  static String groupPage(String groupId) => '/api/android/videoListPagination/groupID/$groupId';
}
