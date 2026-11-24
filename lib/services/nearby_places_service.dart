import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'goong_service.dart';
import 'openmap_service.dart';

/// Represents a named nearby Point of Interest (POI) around a GPS coordinate.
class NearbyPlace {
  final String id;
  final String name;
  final String? address;
  final String? category;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final String source; // 'openmap', 'osm', 'geocode'

  const NearbyPlace({
    required this.id,
    required this.name,
    this.address,
    this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.source,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }
}

/// Fetches and normalizes nearby POIs for one-tap Check-in and Stay Confirmation.
class NearbyPlacesService {
  static final NearbyPlacesService _instance = NearbyPlacesService._internal();
  factory NearbyPlacesService() => _instance;
  NearbyPlacesService._internal();

  /// Computes exact Haversine distance in meters between two coordinates.
  static double distanceBetweenMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _toRad(double deg) => deg * pi / 180.0;

  /// Parses GeoJSON output from OpenMap.vn Nearby API v1.
  static List<NearbyPlace> parseOpenMapGeoJson(
    Map<String, dynamic> data,
    double originLat,
    double originLng,
  ) {
    final features = data['features'];
    if (features is! List) return [];

    final List<NearbyPlace> results = [];
    for (int i = 0; i < features.length; i++) {
      final f = features[i];
      if (f is! Map) continue;

      final coords = f['geometry']?['coordinates'];
      final props = f['properties'];
      if (coords is! List || coords.length < 2 || props is! Map) continue;

      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final rawName = (props['name'] ?? props['short_address'] ?? props['label'])?.toString().trim() ?? '';
      if (rawName.isEmpty) continue;

      final addr = (props['short_address'] ?? props['label'] ?? props['street'])?.toString().trim();
      final categories = props['category'];
      String? categoryLabel;
      if (categories is List && categories.isNotEmpty) {
        categoryLabel = mapCategoryToVietnamese(categories.first?.toString());
      }

      final rawDist = (props['distance'] as num?)?.toDouble();
      final dist = (rawDist != null && rawDist > 0)
          ? rawDist
          : distanceBetweenMeters(originLat, originLng, lat, lng);

      results.add(NearbyPlace(
        id: 'openmap_${props['id'] ?? '${lat}_${lng}_$i'}',
        name: rawName,
        address: addr != null && addr != rawName ? addr : null,
        category: categoryLabel,
        latitude: lat,
        longitude: lng,
        distanceMeters: dist,
        source: 'openmap',
      ));
    }
    return results;
  }

  /// Parses Overpass API JSON elements filtered on named POIs.
  static List<NearbyPlace> parseOverpassJson(
    Map<String, dynamic> data,
    double originLat,
    double originLng,
  ) {
    final elements = data['elements'];
    if (elements is! List) return [];

    final List<NearbyPlace> results = [];
    for (final el in elements) {
      if (el is! Map) continue;

      final tags = el['tags'];
      if (tags is! Map) continue;

      final name = (tags['name:vi'] ?? tags['name'])?.toString().trim() ?? '';
      if (name.isEmpty) continue;

      final double? lat = (el['lat'] as num?)?.toDouble() ??
          (el['center']?['lat'] as num?)?.toDouble();
      final double? lng = (el['lon'] as num?)?.toDouble() ??
          (el['center']?['lon'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final dist = distanceBetweenMeters(originLat, originLng, lat, lng);
      final rawCat = (tags['amenity'] ??
              tags['shop'] ??
              tags['tourism'] ??
              tags['leisure'] ??
              tags['historic'] ??
              tags['office'])
          ?.toString();

      final houseNum = tags['addr:housenumber']?.toString().trim();
      final street = tags['addr:street']?.toString().trim();
      final district = (tags['addr:subdistrict'] ?? tags['addr:district'])?.toString().trim();
      final addrParts = <String>[
        if (houseNum != null && houseNum.isNotEmpty && street != null && street.isNotEmpty)
          '$houseNum $street'
        else if (street != null && street.isNotEmpty)
          street,
        if (district != null && district.isNotEmpty) district,
      ];

      results.add(NearbyPlace(
        id: 'osm_${el['type'] ?? 'n'}_${el['id'] ?? '${lat}_$lng'}',
        name: name,
        address: addrParts.isNotEmpty ? addrParts.join(', ') : null,
        category: mapCategoryToVietnamese(rawCat),
        latitude: lat,
        longitude: lng,
        distanceMeters: dist,
        source: 'osm',
      ));
    }
    return results;
  }

  /// Deduplicates and ranks nearby POIs closest-first.
  static List<NearbyPlace> mergeAndRankPlaces(
    List<NearbyPlace> raw, {
    int limit = 20,
  }) {
    final sorted = List<NearbyPlace>.from(raw)
      ..sort((a, b) {
        final distCmp = a.distanceMeters.compareTo(b.distanceMeters);
        if (distCmp != 0) return distCmp;
        return _sourcePriority(a.source).compareTo(_sourcePriority(b.source));
      });

    final List<NearbyPlace> deduped = [];
    for (final candidate in sorted) {
      final normName = _normalizeName(candidate.name);
      if (normName.isEmpty) continue;

      final existingIdx = deduped.indexWhere((kept) {
        final keptNorm = _normalizeName(kept.name);
        if (keptNorm == normName) return true;
        final withinSameSpot = distanceBetweenMeters(
              kept.latitude,
              kept.longitude,
              candidate.latitude,
              candidate.longitude,
            ) <
            45;
        return withinSameSpot &&
            (keptNorm.contains(normName) || normName.contains(keptNorm));
      });

      if (existingIdx == -1) {
        deduped.add(candidate);
      } else if (_isBetterCandidate(candidate, deduped[existingIdx])) {
        deduped[existingIdx] = candidate;
      }

      if (deduped.length >= limit) break;
    }

    return deduped;
  }

  static String _normalizeName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static int _sourcePriority(String source) {
    switch (source) {
      case 'openmap':
        return 0;
      case 'osm':
        return 1;
      default:
        return 2;
    }
  }

  static bool _isBetterCandidate(NearbyPlace next, NearbyPlace current) {
    if ((next.distanceMeters - current.distanceMeters).abs() < 25) {
      final nextScore = (next.address != null ? 2 : 0) +
          (next.category != null ? 1 : 0) -
          _sourcePriority(next.source);
      final curScore = (current.address != null ? 2 : 0) +
          (current.category != null ? 1 : 0) -
          _sourcePriority(current.source);
      return nextScore > curScore;
    }
    return false;
  }

  /// Maps raw OpenMap/OSM POI category tags into readable Vietnamese labels.
  static String? mapCategoryToVietnamese(String? rawTag) {
    if (rawTag == null || rawTag.trim().isEmpty) return null;
    final key = rawTag.toLowerCase().trim().split('.').last.split(':').last;
    const map = {
      'cafe': 'Quán cà phê',
      'coffee': 'Quán cà phê',
      'restaurant': 'Nhà hàng',
      'fast_food': 'Đồ ăn nhanh',
      'food_court': 'Khu ẩm thực',
      'bar': 'Quán bar',
      'pub': 'Quán bia',
      'bakery': 'Tiệm bánh',
      'hotel': 'Khách sạn',
      'guest_house': 'Nhà nghỉ',
      'hostel': 'Homestay / Hostel',
      'motel': 'Nhà nghỉ',
      'convenience': 'Cửa hàng tiện lợi',
      'supermarket': 'Siêu thị',
      'mall': 'Trung tâm thương mại',
      'department_store': 'Trung tâm thương mại',
      'marketplace': 'Chợ',
      'bank': 'Ngân hàng',
      'atm': 'Cây ATM',
      'pharmacy': 'Nhà thuốc',
      'hospital': 'Bệnh viện',
      'clinic': 'Phòng khám',
      'doctors': 'Phòng khám',
      'school': 'Trường học',
      'university': 'Đại học',
      'college': 'Cao đẳng',
      'kindergarten': 'Mầm non',
      'park': 'Công viên',
      'garden': 'Vườn hoa',
      'playground': 'Khu vui chơi',
      'place_of_worship': 'Đền / Chùa / Nhà thờ',
      'temple': 'Đền / Chùa',
      'pagoda': 'Chùa',
      'museum': 'Bảo tàng',
      'attraction': 'Điểm tham quan',
      'viewpoint': 'Điểm ngắm cảnh',
      'monument': 'Di tích / Tượng đài',
      'memorial': 'Khu tưởng niệm',
      'fuel': 'Trạm xăng',
      'parking': 'Bãi đỗ xe',
      'office': 'Văn phòng',
      'company': 'Công ty',
      'government': 'Cơ quan hành chính',
      'townhall': 'UBND / Trụ sở',
      'police': 'Công an',
      'post_office': 'Bưu điện',
      'cinema': 'Rạp chiếu phim',
      'sports_centre': 'Trung tâm thể thao',
      'fitness_centre': 'Phòng Gym',
      'hairdresser': 'Salon tóc',
      'beauty': 'Spa / Làm đẹp',
      'clothes': 'Thời trang',
      'books': 'Nhà sách',
      'electronics': 'Điện máy',
      'mobile_phone': 'Điện thoại',
    };
    return map[key] ?? rawTag.replaceAll('_', ' ');
  }

  /// Queries OpenMap Nearby (if keyed) & Overpass POI API in parallel with reverse geocode fallback.
  Future<List<NearbyPlace>> fetchNearbyPlaces(
    double lat,
    double lng, {
    double radiusMeters = 350,
    http.Client? client,
  }) async {
    final List<NearbyPlace> gathered = [];

    final openMapFuture = _fetchFromOpenMap(lat, lng, radiusMeters, client: client);
    final overpassFuture = _fetchFromOverpass(lat, lng, radiusMeters, client: client);

    final results = await Future.wait([openMapFuture, overpassFuture]);
    gathered.addAll(results[0]);
    gathered.addAll(results[1]);

    // If few named POIs returned (or offline fallback), append reverse-geocoded street/area
    if (gathered.length < 3) {
      try {
        final addr = await GoongService().reverseGeocode(lat, lng);
        if (addr != null && addr.isNotEmpty) {
          final shortTitle = addr.split(',').first.trim();
          gathered.add(NearbyPlace(
            id: 'geo_${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}',
            name: shortTitle.isNotEmpty ? shortTitle : addr,
            address: addr,
            category: 'Địa chỉ hiện tại',
            latitude: lat,
            longitude: lng,
            distanceMeters: 0,
            source: 'geocode',
          ));
        }
      } catch (_) {}
    }

    return mergeAndRankPlaces(gathered, limit: 20);
  }

  Future<List<NearbyPlace>> _fetchFromOpenMap(
    double lat,
    double lng,
    double radiusMeters, {
    http.Client? client,
  }) async {
    final openmap = OpenMapService();
    if (openmap.apiKey.isEmpty) return [];
    final raw = await openmap.fetchNearbyRaw(
      lat,
      lng,
      radiusKm: radiusMeters / 1000.0,
      size: 15,
      client: client,
    );
    if (raw == null) return [];
    return parseOpenMapGeoJson(raw, lat, lng);
  }

  Future<List<NearbyPlace>> _fetchFromOverpass(
    double lat,
    double lng,
    double radiusMeters, {
    http.Client? client,
  }) async {
    if (GoongService().activeEngine == MapEngineProvider.offline) {
      return [];
    }

    final radius = radiusMeters.round().clamp(100, 1000);
    final query = '[out:json][timeout:5];('
        'nwr(around:$radius,$lat,$lng)[amenity][name];'
        'nwr(around:$radius,$lat,$lng)[shop][name];'
        'nwr(around:$radius,$lat,$lng)[tourism][name];'
        'nwr(around:$radius,$lat,$lng)[leisure][name];'
        'nwr(around:$radius,$lat,$lng)[historic][name];'
        'nwr(around:$radius,$lat,$lng)[office][name];'
        ');out center 25;';

    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            headers: {
              'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic>) {
          return parseOverpassJson(data, lat, lng);
        }
      }
    } catch (_) {
      // Silently ignore network/rate-limit errors; caller uses remaining sources
    } finally {
      if (shouldClose) httpClient.close();
    }
    return [];
  }
}
