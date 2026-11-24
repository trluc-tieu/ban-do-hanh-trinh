import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TileCoord {
  final int z;
  final int x;
  final int y;

  const TileCoord(this.z, this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileCoord &&
          runtimeType == other.runtimeType &&
          z == other.z &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => z.hashCode ^ x.hashCode ^ y.hashCode;

  @override
  String toString() => 'Tile($z, $x, $y)';
}

class OfflineDownloadProgress {
  final int total;
  final int completed;
  final int failed;
  final bool isFinished;
  final String? currentTileInfo;

  const OfflineDownloadProgress({
    required this.total,
    required this.completed,
    required this.failed,
    this.isFinished = false,
    this.currentTileInfo,
  });

  double get percent => total == 0 ? 0 : (completed + failed) / total;
}

class OfflineMapService {
  static final OfflineMapService _instance = OfflineMapService._internal();
  factory OfflineMapService() => _instance;
  OfflineMapService._internal();

  Directory? _cacheDir;
  bool _isDownloading = false;
  bool _cancelRequested = false;

  bool get isDownloading => _isDownloading;

  static const String compliantUserAgent =
      'BanDoHanhTrinh/1.0 (Android; trluc.top.ban_do_hanh_trinh)';

  static String getSourceId(String urlTemplate) {
    if (urlTemplate.contains('google.com')) {
      if (urlTemplate.contains('lyrs=y')) return 'google_hybrid';
      if (urlTemplate.contains('lyrs=s')) return 'google_satellite';
      if (urlTemplate.contains('lyrs=p')) return 'google_terrain';
      return 'google_streets';
    }
    if (urlTemplate.contains('openstreetmap.fr/hot')) return 'osm_hot';
    if (urlTemplate.contains('tile.openstreetmap.org')) return 'osm';
    if (urlTemplate.contains('arcgisonline.com')) return 'esri_satellite';
    if (urlTemplate.contains('opentopomap.org')) return 'topo';
    if (urlTemplate.contains('openmap.vn') || urlTemplate.contains('ndamaps.vn')) return 'openmap_vn';
    return 'custom';
  }

  Future<Directory> getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'offline_tiles'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Get the offline tile file synchronously partitioned by map source
  File? getTileFile(int z, int x, int y, {required String urlTemplate}) {
    if (_cacheDir == null || urlTemplate.isEmpty) return null;
    final sourceId = getSourceId(urlTemplate);
    return File(p.join(_cacheDir!.path, sourceId, '${z}_${x}_$y.png'));
  }

  /// Initialize directory at startup
  Future<void> init() async {
    await getCacheDir();
  }

  /// Slippy map conversion: (lat, lng, zoom) -> (x, y)
  static TileCoord latLngToTile(double lat, double lng, int zoom) {
    final n = 1 << zoom;
    final x = ((lng + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
    final latRad = lat * pi / 180.0;
    final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n).floor().clamp(0, n - 1);
    return TileCoord(zoom, x, y);
  }

  /// Calculate all tiles needed for a center coordinate + radius (km) for specified zoom range
  List<TileCoord> calculateTilesForRadius({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) {
    final double latDelta = radiusKm / 111.0;
    final double cosLat = cos(centerLat * pi / 180.0).abs();
    final double lngDelta = radiusKm / (111.0 * (cosLat < 0.01 ? 0.01 : cosLat));

    final double north = (centerLat + latDelta).clamp(-85.0, 85.0);
    final double south = (centerLat - latDelta).clamp(-85.0, 85.0);
    final double east = (centerLng + lngDelta).clamp(-180.0, 180.0);
    final double west = (centerLng - lngDelta).clamp(-180.0, 180.0);

    return calculateTilesForBounds(
      north: north,
      south: south,
      east: east,
      west: west,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  /// Calculate all tiles needed for a bounding box
  List<TileCoord> calculateTilesForBounds({
    required double north,
    required double south,
    required double east,
    required double west,
    required int minZoom,
    required int maxZoom,
  }) {
    final Set<TileCoord> tiles = {};

    for (int z = minZoom; z <= maxZoom; z++) {
      final nw = latLngToTile(north, west, z);
      final se = latLngToTile(south, east, z);

      final minX = min(nw.x, se.x);
      final maxX = max(nw.x, se.x);
      final minY = min(nw.y, se.y);
      final maxY = max(nw.y, se.y);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tiles.add(TileCoord(z, x, y));
        }
      }
    }

    return tiles.toList();
  }

  /// Request cancel current download
  void cancelDownload() {
    _cancelRequested = true;
  }

  /// Download a list of tiles with progress streaming
  Stream<OfflineDownloadProgress> downloadTiles({
    required List<TileCoord> tiles,
    required String tileUrlTemplate,
    int concurrency = 3,
  }) async* {
    if (_isDownloading) return;
    _isDownloading = true;
    _cancelRequested = false;

    final baseDir = await getCacheDir();
    final sourceId = getSourceId(tileUrlTemplate);
    final sourceDir = Directory(p.join(baseDir.path, sourceId));
    if (!await sourceDir.exists()) {
      await sourceDir.create(recursive: true);
    }

    final client = http.Client();
    int completed = 0;
    int failed = 0;
    final total = tiles.length;

    yield OfflineDownloadProgress(
      total: total,
      completed: 0,
      failed: 0,
      currentTileInfo: 'Bắt đầu tải bản đồ ($sourceId)...',
    );

    // Batch download with concurrency
    for (int i = 0; i < tiles.length; i += concurrency) {
      if (_cancelRequested) {
        break;
      }

      final batch = tiles.sublist(i, min(i + concurrency, tiles.length));
      final futures = batch.map((coord) async {
        final file = File(p.join(sourceDir.path, '${coord.z}_${coord.x}_${coord.y}.png'));
        if (await file.exists() && await file.length() > 500) {
          return true; // Already cached
        }

        final urlStr = tileUrlTemplate
            .replaceAll('{z}', coord.z.toString())
            .replaceAll('{x}', coord.x.toString())
            .replaceAll('{y}', coord.y.toString());

        try {
          final res = await client.get(
            Uri.parse(urlStr),
            headers: {
              'User-Agent': compliantUserAgent,
            },
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200 && res.bodyBytes.length > 500) {
            await file.writeAsBytes(res.bodyBytes);
            return true;
          }
        } catch (_) {}
        return false;
      });

      final results = await Future.wait(futures);
      for (final success in results) {
        if (success) {
          completed++;
        } else {
          failed++;
        }
      }

      yield OfflineDownloadProgress(
        total: total,
        completed: completed,
        failed: failed,
        currentTileInfo: 'Đã tải ô $completed / $total...',
      );
    }

    client.close();
    _isDownloading = false;

    yield OfflineDownloadProgress(
      total: total,
      completed: completed,
      failed: failed,
      isFinished: true,
      currentTileInfo: _cancelRequested ? 'Đã dừng tải.' : 'Hoàn tất tải $completed ô bản đồ!',
    );
  }

  /// Get storage stats: number of cached tiles & total size in bytes
  Future<({int count, int totalBytes})> getOfflineStats() async {
    try {
      final dir = await getCacheDir();
      final entities = dir.listSync(recursive: true);
      int count = 0;
      int totalBytes = 0;

      for (final e in entities) {
        if (e is File && e.path.endsWith('.png')) {
          count++;
          totalBytes += e.lengthSync();
        }
      }
      return (count: count, totalBytes: totalBytes);
    } catch (_) {
      return (count: 0, totalBytes: 0);
    }
  }

  /// Clear all offline tiles
  Future<void> clearOfflineTiles() async {
    try {
      final dir = await getCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }
}
