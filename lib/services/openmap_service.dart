import 'dart:convert';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;

class _ApiKeyInjectorHttpClient extends http.BaseClient {
  final http.Client _inner;
  final String apiKey;

  _ApiKeyInjectorHttpClient(this._inner, this.apiKey);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final lower = request.url.toString().toLowerCase();
    final isOpenMapHost = lower.contains('openmap.vn') || lower.contains('ndamaps.vn');

    http.BaseRequest targetRequest = request;
    if (isOpenMapHost && apiKey.isNotEmpty && !request.url.queryParameters.containsKey('apikey')) {
      final newParams = Map<String, String>.from(request.url.queryParameters);
      newParams['apikey'] = apiKey;
      final newUri = request.url.replace(queryParameters: newParams);

      if (request is http.Request) {
        final copy = http.Request(request.method, newUri)
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;
        targetRequest = copy;
      }
    }

    targetRequest.headers.putIfAbsent(
      'User-Agent',
      () => 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
    );
    return _inner.send(targetRequest);
  }

  @override
  void close() {
    _inner.close();
  }
}

class OpenMapService {
  static final OpenMapService _instance = OpenMapService._internal();
  factory OpenMapService() => _instance;
  OpenMapService._internal();

  /// OpenMap.vn / NDAMaps.vn API Key (created at https://enterprise.openmap.vn/)
  String apiKey = '';

  /// Domain preference: 'openmap.vn' or 'ndamaps.vn'
  String domain = 'openmap.vn';

  /// Custom style JSON URL if user overrides default styles
  String? customTileUrl;

  void setApiKey(String key) {
    apiKey = key.trim();
  }

  void setDomain(String d) {
    if (d.contains('ndamaps')) {
      domain = 'ndamaps.vn';
    } else {
      domain = 'openmap.vn';
    }
  }

  void setCustomTileUrl(String? url) {
    customTileUrl = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  }

  /// Ensures `{key}` placeholder and missing `?apikey=` query parameter are resolved
  /// while keeping `{z}/{x}/{y}` placeholders intact.
  static String ensureApiKeyInUrl(String url, String key) {
    if (key.isEmpty || url.isEmpty) return url;
    String result = url.replaceAll('{key}', key);
    final lower = result.toLowerCase();
    final isOpenMapHost = lower.contains('openmap.vn') || lower.contains('ndamaps.vn');
    if (isOpenMapHost && !lower.contains('apikey=')) {
      final separator = result.contains('?') ? '&' : '?';
      result = '$result${separator}apikey=${Uri.encodeQueryComponent(key)}';
    }
    return result;
  }

  /// Vector Style JSON URL for MapLibre/flutter_map_vector_tiles
  String getVectorStyleUrl({String styleId = 'day-v1', String? customKey}) {
    final key = (customKey != null && customKey.isNotEmpty) ? customKey : apiKey;
    if (customTileUrl != null && customTileUrl!.isNotEmpty) {
      return ensureApiKeyInUrl(customTileUrl!, key);
    }
    final base = 'https://maptiles.$domain/styles/$styleId/style.json';
    return key.isNotEmpty ? '$base?apikey=${Uri.encodeQueryComponent(key)}' : base;
  }

  /// Backward-compatible URL getter returning active day vector style URL
  String getTileUrl({String styleId = 'day-v1'}) => getVectorStyleUrl(styleId: styleId);

  /// Loads and compiles an OpenMap.vn / NDAMaps MapLibre vector style
  Future<vt.Style> loadVectorStyle({
    String styleId = 'day-v1',
    String? customKey,
    vt.Logger logger = const vt.Logger.noop(),
  }) async {
    final key = (customKey != null && customKey.isNotEmpty) ? customKey : apiKey;
    if (key.isEmpty) {
      throw Exception(
        'Chưa nhập OpenMap / NDAMaps API Key. Hãy tạo key tại enterprise.openmap.vn và lưu trong Cài đặt.',
      );
    }

    final styleUri = getVectorStyleUrl(styleId: styleId, customKey: key);
    final client = _ApiKeyInjectorHttpClient(http.Client(), key);

    try {
      final rawStyle = await vt.StyleReader(
        uri: styleUri,
        apiKey: key,
        httpClient: client,
        headers: const {
          'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
        },
        logger: logger,
      ).read();

      final fixedProviders = <String, vt.VectorTileProvider>{};
      for (final entry in rawStyle.providers.providers.entries) {
        final provider = entry.value;
        if (provider is vt.NetworkVectorTileProvider) {
          final fixedTemplate = ensureApiKeyInUrl(provider.urlTemplate, key);
          if (fixedTemplate != provider.urlTemplate) {
            provider.dispose();
            fixedProviders[entry.key] = vt.NetworkVectorTileProvider(
              urlTemplate: fixedTemplate,
              headers: provider.headers,
              minimumZoom: provider.minimumZoom,
              maximumZoom: provider.maximumZoom,
              logger: provider.logger,
            );
          } else {
            fixedProviders[entry.key] = provider;
          }
        } else {
          fixedProviders[entry.key] = provider;
        }
      }

      final fixedRasters = <String, vt.RasterTileSource>{};
      for (final entry in rawStyle.rasterSources.entries) {
        final raster = entry.value;
        final provider = raster.provider;
        if (provider is vt.NetworkVectorTileProvider) {
          final fixedTemplate = ensureApiKeyInUrl(provider.urlTemplate, key);
          if (fixedTemplate != provider.urlTemplate) {
            provider.dispose();
            fixedRasters[entry.key] = vt.RasterTileSource(
              provider: vt.NetworkVectorTileProvider(
                urlTemplate: fixedTemplate,
                headers: provider.headers,
                minimumZoom: provider.minimumZoom,
                maximumZoom: provider.maximumZoom,
                logger: provider.logger,
              ),
              tileSize: raster.tileSize,
              encoding: raster.encoding,
            );
          } else {
            fixedRasters[entry.key] = raster;
          }
        } else {
          fixedRasters[entry.key] = raster;
        }
      }

      return vt.Style(
        theme: rawStyle.theme,
        providers: vt.TileProviders(
          fixedProviders,
          promoteIds: rawStyle.providers.promoteIds,
        ),
        rasterSources: fixedRasters,
        sprites: rawStyle.sprites,
        glyphs: rawStyle.glyphs,
        center: rawStyle.center,
        zoom: rawStyle.zoom,
        name: rawStyle.name,
        attributions: rawStyle.attributions,
      );
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  /// Verify whether the OpenMap / NDAMaps key can access Vector Style JSON
  Future<({bool ok, String message})> testStyleConnection({
    String? customKey,
    String styleId = 'day-v1',
  }) async {
    final key = (customKey != null && customKey.isNotEmpty) ? customKey : apiKey;
    if (key.isEmpty) {
      return (ok: false, message: 'Chưa có API Key.');
    }

    try {
      final url = Uri.parse(getVectorStyleUrl(styleId: styleId, customKey: key));
      final response = await http.get(url, headers: {
        'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is Map && data.containsKey('layers')) {
          final styleName = data['name'] ?? styleId;
          return (ok: true, message: 'Hợp lệ! Đã tải được Style "$styleName".');
        }
        return (ok: false, message: 'Phản hồi không phải định dạng Vector Style JSON.');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return (ok: false, message: 'HTTP ${response.statusCode}: Key không hợp lệ hoặc chưa bật quyền Map Tiles.');
      }
      return (ok: false, message: 'HTTP ${response.statusCode}: Không thể tải Style bản đồ.');
    } catch (e) {
      return (ok: false, message: 'Lỗi mạng hoặc Timeout: $e');
    }
  }

  /// Reverse geocode coordinates to detailed Vietnamese address
  /// Uses official Openmap.vn / NDAMaps.vn Reverse Geocoding API v1
  Future<String?> reverseGeocode(double lat, double lng, {String? customKey}) async {
    final key = (customKey != null && customKey.isNotEmpty) ? customKey : apiKey;
    if (key.isEmpty) return null;

    try {
      final url = Uri.parse(
        'https://mapapis.$domain/v1/geocode/reverse?latlng=$lat,$lng&apikey=$key&admin_v2=true',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['results'] != null && (data['results'] as List).isNotEmpty) {
          final first = data['results'][0];
          final formatted = first['formatted_address'] as String?;
          if (formatted != null && formatted.isNotEmpty) return formatted;
          final addr = first['address'] as String?;
          if (addr != null && addr.isNotEmpty) return addr;
          final name = first['name'] as String?;
          if (name != null && name.isNotEmpty) return name;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Forward search places and POIs across Vietnam using Openmap Forward Geocode
  Future<List<Map<String, dynamic>>> searchPlaces(String query, {String? customKey}) async {
    final key = (customKey != null && customKey.isNotEmpty) ? customKey : apiKey;
    if (key.isEmpty) return [];

    try {
      final url = Uri.parse(
        'https://mapapis.$domain/v1/geocode/forward?address=${Uri.encodeComponent(query)}&apikey=$key&admin_v2=true',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['results'] != null) {
          final List<Map<String, dynamic>> results = [];
          for (final f in data['results']) {
            final loc = f['geometry']?['location'];
            if (loc != null) {
              results.add({
                'name': f['name'] ?? f['formatted_address'],
                'label': f['formatted_address'] ?? f['address'],
                'latitude': (loc['lat'] as num).toDouble(),
                'longitude': (loc['lng'] as num).toDouble(),
              });
            }
          }
          return results;
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetch nearby GeoJSON FeatureCollection from OpenMap.vn Nearby API v1
  Future<Map<String, dynamic>?> fetchNearbyRaw(
    double lat,
    double lng, {
    double radiusKm = 0.35,
    int size = 15,
    String? customKey,
    http.Client? client,
  }) async {
    final key = (customKey != null && customKey.isNotEmpty) ? customKey : apiKey;
    if (key.isEmpty) return null;

    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final url = Uri.parse(
        'https://mapapis.$domain/v1/nearby?size=$size&point.lon=$lng&point.lat=$lat&boundary.circle.radius=$radiusKm&apikey=$key',
      );
      final response = await httpClient.get(url, headers: {
        'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {
      // Ignored: caller handles fallback providers cleanly
    } finally {
      if (shouldClose) httpClient.close();
    }
    return null;
  }
}
