import 'data/services/cinemana_api.dart';
import 'tv_library.dart';
import 'tv_downloads.dart';
import 'tv_playback_preferences.dart';
import 'tv_channel_favorites.dart';

final CinemanaApi tvApi = CinemanaApi();
final TvLibraryStore tvLibrary = TvLibraryStore();

final TvDownloadStore tvDownloads = TvDownloadStore();

final TvPlaybackPreferences tvPlaybackPreferences = TvPlaybackPreferences();
final TvChannelFavorites tvChannelFavorites = TvChannelFavorites();
