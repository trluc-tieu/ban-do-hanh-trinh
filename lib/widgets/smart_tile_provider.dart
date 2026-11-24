import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/offline_map_service.dart';

/// Smart tile provider that checks local offline storage first before requesting network tiles
/// Uses standard compliant User-Agent to avoid OpenStreetMap 403 Access Blocked errors
class SmartTileProvider extends TileProvider {
  final NetworkTileProvider _networkProvider;

  static const String defaultUserAgent =
      'BanDoHanhTrinh/1.0 (Android; trluc.top.ban_do_hanh_trinh; contact trluc@top)';

  SmartTileProvider({
    Map<String, String>? headers,
    NetworkTileProvider? networkProvider,
  })  : _networkProvider = networkProvider ??
            NetworkTileProvider(
              headers: {
                'User-Agent': defaultUserAgent,
                ...?headers,
              },
              silenceExceptions: true,
              attemptDecodeOfHttpErrorResponses: false,
            ),
        super(
          headers: {
            'User-Agent': defaultUserAgent,
            ...?headers,
          },
        );

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    try {
      final offlineFile = OfflineMapService().getTileFile(
        coordinates.z,
        coordinates.x,
        coordinates.y,
        urlTemplate: options.urlTemplate ?? '',
      );
      if (offlineFile != null && offlineFile.existsSync() && offlineFile.lengthSync() > 500) {
        return FileImage(offlineFile);
      }
    } catch (_) {}

    return _networkProvider.getImageWithCancelLoadingSupport(
      coordinates,
      options,
      cancelLoading,
    );
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    try {
      final offlineFile = OfflineMapService().getTileFile(
        coordinates.z,
        coordinates.x,
        coordinates.y,
        urlTemplate: options.urlTemplate ?? '',
      );
      if (offlineFile != null && offlineFile.existsSync() && offlineFile.lengthSync() > 500) {
        return FileImage(offlineFile);
      }
    } catch (_) {}

    return _networkProvider.getImage(coordinates, options);
  }

  @override
  Future<void> dispose() async {
    await _networkProvider.dispose();
    super.dispose();
  }
}
