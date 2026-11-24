import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/province_stats.dart';
import 'openmap_service.dart';

enum MapEngineProvider {
  google,
  openmap,
  offline,
}

enum MapStyleType {
  // Google Maps (Tiếng Việt siêu nhanh, cập nhật nhất)
  googleStreets,   // Google Maps Tiêu Chuẩn (Đường phố tiếng Việt)
  googleHybrid,    // Google Maps Vệ Tinh Lai (Vệ tinh kèm tên đường/phố)
  googleSatellite, // Google Maps Vệ Tinh Thuần
  googleTerrain,   // Google Maps Địa Hình

  // OpenStreetMap (Miễn phí, chuẩn quốc tế, đã fix User-Agent 403)
  openStreetMap,   // OpenStreetMap Tiêu Chuẩn
  osmHot,          // OpenStreetMap Tiếng Việt (HOT)

  // OpenMap.vn / NDAMaps (Bản đồ số Việt Nam - Vector Tiles)
  openmapVn,         // OpenMap.vn / NDAMaps (Ban ngày - day-v1)

  // Vệ tinh & Địa hình mở khác
  esriSatellite,     // Vệ tinh ESRI World Imagery
  topo,              // Địa hình OpenTopoMap

  // Bổ sung chế độ OpenMap.vn / NDAMaps (giữ nguyên index cũ để tránh lệch setting)
  openmapVnNight,    // OpenMap.vn / NDAMaps (Ban đêm - night-v1)
  openmapVnSatellite,// OpenMap.vn / NDAMaps (Vệ tinh - satellite-v1)
}

class GoongService {
  static final GoongService _instance = GoongService._internal();
  factory GoongService() => _instance;
  GoongService._internal();

  MapEngineProvider activeEngine = MapEngineProvider.google;

  // Google Maps API Key (optional, for Google Geocoding REST API)
  String googleApiKey = '';

  void setGoogleApiKey(String key) {
    googleApiKey = key.trim();
  }

  void setActiveEngine(MapEngineProvider engine) {
    activeEngine = engine;
  }

  /// Backward compatibility helper
  void setKeys({String? mapKey, String? restKey}) {
    if (restKey != null && restKey.isNotEmpty) googleApiKey = restKey;
  }

  static bool isVectorStyle(MapStyleType style) {
    return style == MapStyleType.openmapVn ||
        style == MapStyleType.openmapVnNight ||
        style == MapStyleType.openmapVnSatellite;
  }

  static String vectorStyleId(MapStyleType style) {
    switch (style) {
      case MapStyleType.openmapVnNight:
        return 'night-v1';
      case MapStyleType.openmapVnSatellite:
        return 'satellite-v1';
      case MapStyleType.openmapVn:
      default:
        return 'day-v1';
    }
  }

  /// Get raster tile URL or vector style URL template based on selected map style
  /// Shows EXACTLY what the user chooses, 100% transparent!
  String getTileUrl(MapStyleType style) {
    switch (style) {
      case MapStyleType.googleStreets:
        return 'https://mt1.google.com/vt/lyrs=m&hl=vi&gl=VN&x={x}&y={y}&z={z}';
      case MapStyleType.googleHybrid:
        return 'https://mt1.google.com/vt/lyrs=y&hl=vi&gl=VN&x={x}&y={y}&z={z}';
      case MapStyleType.googleSatellite:
        return 'https://mt1.google.com/vt/lyrs=s&hl=vi&gl=VN&x={x}&y={y}&z={z}';
      case MapStyleType.googleTerrain:
        return 'https://mt1.google.com/vt/lyrs=p&hl=vi&gl=VN&x={x}&y={y}&z={z}';
      case MapStyleType.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapStyleType.osmHot:
        return 'https://tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
      case MapStyleType.openmapVn:
        return OpenMapService().getVectorStyleUrl(styleId: 'day-v1');
      case MapStyleType.openmapVnNight:
        return OpenMapService().getVectorStyleUrl(styleId: 'night-v1');
      case MapStyleType.openmapVnSatellite:
        return OpenMapService().getVectorStyleUrl(styleId: 'satellite-v1');
      case MapStyleType.esriSatellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapStyleType.topo:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
    }
  }

  /// Reverse geocode coordinates based on active engine
  Future<String?> reverseGeocode(double lat, double lng) async {
    // 1. If Offline mode chosen: immediate offline province match
    if (activeEngine == MapEngineProvider.offline) {
      final province = VietnamProvinces.matchProvince(lat, lng, null);
      return 'Toạ độ: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)} ($province)';
    }

    // 2. If OpenMap.vn / NDAMaps active:
    if (activeEngine == MapEngineProvider.openmap) {
      final openmapAddr = await OpenMapService().reverseGeocode(lat, lng);
      if (openmapAddr != null && openmapAddr.isNotEmpty) {
        return openmapAddr;
      }
    }

    // 3. If Google Maps active:
    if (activeEngine == MapEngineProvider.google && googleApiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&language=vi&key=$googleApiKey',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          if (data['results'] != null && (data['results'] as List).isNotEmpty) {
            final formatted = data['results'][0]['formatted_address'] as String?;
            if (formatted != null && formatted.isNotEmpty) {
              return formatted;
            }
          }
        }
      } catch (_) {}
    }

    // 4. OpenMap.vn fallback if key is available
    if (OpenMapService().apiKey.isNotEmpty) {
      final openmapAddr = await OpenMapService().reverseGeocode(lat, lng);
      if (openmapAddr != null && openmapAddr.isNotEmpty) {
        return openmapAddr;
      }
    }

    // 5. OpenStreetMap Nominatim reverse geocode (compliant User-Agent)
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'BanDoHanhTrinhApp/1.0 (Android; trluc.top)',
        },
      ).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final name = data['display_name'] as String?;
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}

    // 6. Final Offline Fallback: Local Vietnam Province Resolver (100% Offline)
    final province = VietnamProvinces.matchProvince(lat, lng, null);
    return 'Toạ độ: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)} ($province)';
  }
}
