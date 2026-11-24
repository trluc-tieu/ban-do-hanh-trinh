import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/pinned_place.dart';
import 'goong_service.dart';
import 'nearby_places_service.dart';
import 'openmap_service.dart';

/// A single place or address returned by forward text search.
class PlaceSearchResult {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? rawType;
  final double? distanceMeters;

  const PlaceSearchResult({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.rawType,
    this.distanceMeters,
  });

  String? get formattedDistance {
    final d = distanceMeters;
    if (d == null || d <= 0) return null;
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  /// Infers the best matching [PinnedPlaceCategory] from place name & type tags.
  PinnedPlaceCategory? get suggestedCategory =>
      PlaceSearchService.inferCategory(name, address: address, rawType: rawType);
}

/// Forward place & address search service supporting:
/// 1. Direct `"lat, lng"` coordinate input
/// 2. OpenMap.vn / NDAMaps Forward Geocode & Autocomplete (when API key is set)
/// 3. Google Maps Geocoding API (when Google API key is set)
/// 4. OpenStreetMap Nominatim Search (free, no key required, Vietnamese prioritized)
/// 5. Offline 63-Province / City fallback
class PlaceSearchService {
  static final PlaceSearchService _instance = PlaceSearchService._internal();
  factory PlaceSearchService() => _instance;
  PlaceSearchService._internal();

  static const Map<String, String> _headers = {
    'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
    'Accept-Language': 'vi,en;q=0.8',
  };

  /// Parses direct `"lat, lng"` coordinate text if the user pastes coordinates.
  static PlaceSearchResult? tryParseCoordinates(String rawQuery) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(rawQuery);
    if (match == null) return null;

    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    return PlaceSearchResult(
      id: 'coord_${lat}_$lng',
      name: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      address: 'Toạ độ GPS trực tiếp',
      latitude: lat,
      longitude: lng,
      rawType: 'coordinate',
    );
  }

  /// Infers a [PinnedPlaceCategory] from Vietnamese keywords or OSM/Google type tags.
  static PinnedPlaceCategory? inferCategory(
    String name, {
    String? address,
    String? rawType,
  }) {
    final text = '${name.toLowerCase()} ${(rawType ?? '').toLowerCase()}';

    if (RegExp(r'(đại học|trường|tiểu học|thcs|thpt|mầm non|học viện|university|school|college|kindergarten)')
        .hasMatch(text)) {
      return PinnedPlaceCategory.school;
    }
    if (RegExp(r'(cà phê|cafe|coffee|trà sữa|highlands|phúc long|starbucks|the coffee)')
        .hasMatch(text)) {
      return PinnedPlaceCategory.cafe;
    }
    if (RegExp(r'(nhà hàng|quán ăn|bún|phở|cơm|lẩu|nướng|ẩm thực|buffet|restaurant|fast_food|bakery|food)')
        .hasMatch(text)) {
      return PinnedPlaceCategory.restaurant;
    }
    if (RegExp(r'(bãi đỗ xe|bãi gửi xe|bãi xe|nhà xe|parking)')
        .hasMatch(text)) {
      return PinnedPlaceCategory.parking;
    }
    if (RegExp(r'(công ty|văn phòng|cơ quan|toà nhà|tòa nhà|khu công nghiệp|nhà máy|trụ sở|ubnd|office|company|industrial|commercial)')
        .hasMatch(text)) {
      return PinnedPlaceCategory.work;
    }
    if (RegExp(r'(công viên|hồ |chùa|đền|nhà thờ|bảo tàng|khu du lịch|bãi biển|đỉnh |núi |thác |di tích|danh thắng|park|tourism|attraction|museum|viewpoint|beach|peak)')
        .hasMatch(text)) {
      return PinnedPlaceCategory.scenic;
    }
    return null;
  }

  /// Parses OpenStreetMap Nominatim `jsonv2` search array.
  static List<PlaceSearchResult> parseNominatimJson(
    List<dynamic> items, {
    double? refLat,
    double? refLng,
  }) {
    final List<PlaceSearchResult> out = [];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) continue;

      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lng = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lng == null) continue;

      final displayName = (item['display_name']?.toString() ?? '').trim();
      String title = (item['name']?.toString() ?? '').trim();
      if (title.isEmpty && displayName.isNotEmpty) {
        title = displayName.split(',').first.trim();
      }
      if (title.isEmpty) continue;

      final dist = (refLat != null && refLng != null)
          ? NearbyPlacesService.distanceBetweenMeters(refLat, refLng, lat, lng)
          : null;

      out.add(PlaceSearchResult(
        id: 'nom_${item['place_id'] ?? i}',
        name: title,
        address: displayName.isNotEmpty ? displayName : title,
        latitude: lat,
        longitude: lng,
        rawType: '${item['category'] ?? ''}_${item['type'] ?? ''}',
        distanceMeters: dist,
      ));
    }
    return out;
  }

  /// Parses Google Geocoding JSON response.
  static List<PlaceSearchResult> parseGoogleGeocodeJson(
    Map<String, dynamic> data, {
    double? refLat,
    double? refLng,
  }) {
    final results = data['results'];
    if (results is! List) return [];

    final List<PlaceSearchResult> out = [];
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      if (r is! Map) continue;
      final loc = r['geometry']?['location'];
      if (loc is! Map) continue;

      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final formatted = (r['formatted_address']?.toString() ?? '').trim();
      String title = '';
      final comps = r['address_components'];
      if (comps is List && comps.isNotEmpty && comps.first is Map) {
        title = (comps.first['long_name']?.toString() ?? '').trim();
      }
      if (title.isEmpty && formatted.isNotEmpty) {
        title = formatted.split(',').first.trim();
      }
      if (title.isEmpty) continue;

      final types = (r['types'] is List) ? (r['types'] as List).join(' ') : null;
      final dist = (refLat != null && refLng != null)
          ? NearbyPlacesService.distanceBetweenMeters(refLat, refLng, lat, lng)
          : null;

      out.add(PlaceSearchResult(
        id: 'gg_${r['place_id'] ?? i}',
        name: title,
        address: formatted.isNotEmpty ? formatted : title,
        latitude: lat,
        longitude: lng,
        rawType: types,
        distanceMeters: dist,
      ));
    }
    return out;
  }

  /// Searches places nationwide (or globally) by text query.
  Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    double? biasLat,
    double? biasLng,
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final List<PlaceSearchResult> collected = [];

    // 1. Direct coordinate pair check ("21.0285, 105.8542")
    final coordHit = tryParseCoordinates(q);
    if (coordHit != null) {
      collected.add(coordHit);
    }

    final engine = GoongService().activeEngine;

    if (engine != MapEngineProvider.offline) {
      // 2. OpenMap.vn / NDAMaps Forward Geocode + Autocomplete (if API key present)
      if (OpenMapService().apiKey.isNotEmpty) {
        final omResults = await _searchOpenMap(q, biasLat: biasLat, biasLng: biasLng);
        collected.addAll(omResults);
      }

      // 3. Google Geocoding API (if Google API key present)
      if (GoongService().googleApiKey.isNotEmpty && collected.length < limit) {
        final ggResults = await _searchGoogle(q, biasLat: biasLat, biasLng: biasLng);
        collected.addAll(ggResults);
      }

      // 4. OpenStreetMap Nominatim (Free, works without any API key)
      if (collected.length < limit) {
        var nomResults = await _searchNominatim(
          q,
          countryCode: 'vn',
          refLat: biasLat,
          refLng: biasLng,
          limit: limit,
        );
        if (nomResults.isEmpty) {
          // Retry globally if user searched an overseas place
          nomResults = await _searchNominatim(
            q,
            countryCode: null,
            refLat: biasLat,
            refLng: biasLng,
            limit: limit,
          );
        }
        collected.addAll(nomResults);
      }
    }

    // 5. Offline fallback: match Vietnam's 63 provinces/cities locally
    if (collected.isEmpty) {
      collected.addAll(_searchOfflineProvinces(q, refLat: biasLat, refLng: biasLng));
    }

    return _deduplicate(collected, limit: limit);
  }

  Future<List<PlaceSearchResult>> _searchOpenMap(
    String query, {
    double? biasLat,
    double? biasLng,
  }) async {
    final om = OpenMapService();
    final key = om.apiKey;
    if (key.isEmpty) return [];

    final List<PlaceSearchResult> results = [];

    // Try OpenMap Autocomplete v1 first (rich POI names)
    try {
      final focusParams = (biasLat != null && biasLng != null)
          ? '&focus.point.lat=$biasLat&focus.point.lon=$biasLng'
          : '';
      final autoUrl = Uri.parse(
        'https://mapapis.${om.domain}/v1/autocomplete?text=${Uri.encodeComponent(query)}$focusParams&apikey=$key',
      );
      final resp = await http.get(autoUrl, headers: _headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        final features = data is Map ? data['features'] : null;
        if (features is List) {
          for (int i = 0; i < features.length; i++) {
            final f = features[i];
            if (f is! Map) continue;
            final coords = f['geometry']?['coordinates'];
            final props = f['properties'];
            if (coords is List && coords.length >= 2 && props is Map) {
              final lng = (coords[0] as num?)?.toDouble();
              final lat = (coords[1] as num?)?.toDouble();
              if (lat == null || lng == null) continue;
              final name = (props['name'] ?? props['label'] ?? '').toString().trim();
              final label = (props['label'] ?? props['short_address'] ?? name).toString().trim();
              if (name.isEmpty) continue;
              final dist = (biasLat != null && biasLng != null)
                  ? NearbyPlacesService.distanceBetweenMeters(biasLat, biasLng, lat, lng)
                  : null;
              results.add(PlaceSearchResult(
                id: 'om_auto_${props['id'] ?? i}',
                name: name,
                address: label,
                latitude: lat,
                longitude: lng,
                rawType: props['layer']?.toString(),
                distanceMeters: dist,
              ));
            }
          }
        }
      }
    } catch (_) {}

    if (results.isNotEmpty) return results;

    // Fallback to OpenMap Forward Geocode v1
    try {
      final forwardList = await om.searchPlaces(query);
      for (int i = 0; i < forwardList.length; i++) {
        final item = forwardList[i];
        final lat = (item['latitude'] as num?)?.toDouble();
        final lng = (item['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final name = (item['name']?.toString() ?? '').trim();
        final label = (item['label']?.toString() ?? name).trim();
        if (name.isEmpty) continue;
        final dist = (biasLat != null && biasLng != null)
            ? NearbyPlacesService.distanceBetweenMeters(biasLat, biasLng, lat, lng)
            : null;
        results.add(PlaceSearchResult(
          id: 'om_fwd_$i',
          name: name,
          address: label,
          latitude: lat,
          longitude: lng,
          distanceMeters: dist,
        ));
      }
    } catch (_) {}

    return results;
  }

  Future<List<PlaceSearchResult>> _searchGoogle(
    String query, {
    double? biasLat,
    double? biasLng,
  }) async {
    final key = GoongService().googleApiKey;
    if (key.isEmpty) return [];
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&region=vn&language=vi&key=$key',
      );
      final resp = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        if (data is Map<String, dynamic>) {
          return parseGoogleGeocodeJson(data, refLat: biasLat, refLng: biasLng);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<List<PlaceSearchResult>> _searchNominatim(
    String query, {
    String? countryCode = 'vn',
    double? refLat,
    double? refLng,
    int limit = 8,
  }) async {
    try {
      final ccParam = countryCode != null ? '&countrycodes=$countryCode' : '';
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=jsonv2&addressdetails=1&limit=$limit$ccParam',
      );
      final resp = await http.get(url, headers: _headers).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        if (data is List) {
          return parseNominatimJson(data, refLat: refLat, refLng: refLng);
        }
      }
    } catch (_) {}
    return [];
  }

  static const Map<String, List<double>> _offlineVietnamPlaces = {
    'Hà Nội': [21.02851, 105.85444],
    'TP. Hồ Chí Minh': [10.77689, 106.70098],
    'Đà Nẵng': [16.05441, 108.20217],
    'Hải Phòng': [20.84491, 106.68808],
    'Cần Thơ': [10.04516, 105.74685],
    'Đà Lạt (Lâm Đồng)': [11.94042, 108.45831],
    'Nha Trang (Khánh Hoà)': [12.23879, 109.19675],
    'Sa Pa (Lào Cai)': [22.33636, 103.84379],
    'Hạ Long (Quảng Ninh)': [20.95108, 107.07336],
    'Huế (Thừa Thiên Huế)': [16.46371, 107.59087],
    'Hội An (Quảng Nam)': [15.88006, 108.33805],
    'Vũng Tàu (Bà Rịa - Vũng Tàu)': [10.34599, 107.08426],
    'Quy Nhơn (Bình Định)': [13.78297, 109.21966],
    'Phú Quốc (Kiên Giang)': [10.22702, 103.95716],
    'Ninh Bình': [20.25061, 105.97445],
    'Hà Giang': [22.82333, 104.98357],
    'Vinh (Nghệ An)': [18.67958, 105.68133],
    'Thanh Hoá': [19.80669, 105.78518],
    'Buôn Ma Thuột (Đắk Lắk)': [12.66667, 108.05000],
    'Biên Hoà (Đồng Nai)': [10.95741, 106.84269],
    'Thủ Dầu Một (Bình Dương)': [10.98040, 106.65191],
  };

  List<PlaceSearchResult> _searchOfflineProvinces(
    String query, {
    double? refLat,
    double? refLng,
  }) {
    final qLower = _stripAccents(query.toLowerCase());
    final List<PlaceSearchResult> matches = [];
    _offlineVietnamPlaces.forEach((placeName, coords) {
      if (placeName.toLowerCase().contains(query.toLowerCase()) ||
          _stripAccents(placeName.toLowerCase()).contains(qLower)) {
        final lat = coords[0];
        final lng = coords[1];
        final dist = (refLat != null && refLng != null)
            ? NearbyPlacesService.distanceBetweenMeters(refLat, refLng, lat, lng)
            : null;
        matches.add(PlaceSearchResult(
          id: 'offline_$placeName',
          name: placeName,
          address: '$placeName, Việt Nam (Ngoại tuyến)',
          latitude: lat,
          longitude: lng,
          rawType: 'administrative',
          distanceMeters: dist,
        ));
      }
    });
    return matches;
  }

  static List<PlaceSearchResult> _deduplicate(
    List<PlaceSearchResult> list, {
    required int limit,
  }) {
    final List<PlaceSearchResult> unique = [];
    for (final item in list) {
      final dup = unique.any((u) {
        final dist = NearbyPlacesService.distanceBetweenMeters(
          u.latitude,
          u.longitude,
          item.latitude,
          item.longitude,
        );
        return dist < 35 &&
            u.name.toLowerCase().trim() == item.name.toLowerCase().trim();
      });
      if (!dup) {
        unique.add(item);
        if (unique.length >= limit) break;
      }
    }
    return unique;
  }

  static String _stripAccents(String input) {
    const vietnamese =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const latin =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var result = input;
    for (int i = 0; i < vietnamese.length; i++) {
      result = result.replaceAll(vietnamese[i], latin[i]);
    }
    return result;
  }
}
