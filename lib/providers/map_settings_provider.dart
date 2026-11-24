import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vehicle_type.dart';
import '../services/goong_service.dart';
import '../services/openmap_service.dart';

class MapSettingsProvider with ChangeNotifier {
  MapEngineProvider _activeEngine = MapEngineProvider.google;
  MapStyleType _mapStyle = MapStyleType.googleStreets; // Default to crisp Vietnamese Google Maps
  String _googleApiKey = '';
  String _openmapApiKey = '';
  String _openmapDomain = 'openmap.vn';
  String _openmapCustomTileUrl = '';
  int _distanceFilter = 5; // meters
  bool _showFogOfWar = true;
  bool _autoCenter = true;
  bool _autoStopWhenStationary = true;
  int _autoStopStationaryMinutes = 15; // default 15 minutes

  // Background automatic trip detection
  bool _backgroundAutoTrack = false;
  double _autoTrackMinSpeedKmh = 12.0;
  int _autoTrackMinRangeMeters = 150;

  // Vehicle marker customization
  VehicleType _vehicleType = VehicleType.motorbike;
  int _vehicleColorValue = kVehicleColors.first.toARGB32();
  bool _rotateMapWithHeading = true;

  // Home pin ("Nhà") - tighter default radius 50m
  double? _homeLat;
  double? _homeLng;
  int _homeRadiusMeters = 50;

  // Optional GitHub token for checking/downloading updates from a private repository
  String _githubUpdateToken = '';

  String get githubUpdateToken => _githubUpdateToken;

  bool get backgroundAutoTrack => _backgroundAutoTrack;
  double get autoTrackMinSpeedKmh => _autoTrackMinSpeedKmh;
  int get autoTrackMinRangeMeters => _autoTrackMinRangeMeters;
  VehicleType get vehicleType => _vehicleType;
  Color get vehicleColor => Color(_vehicleColorValue);
  bool get rotateMapWithHeading => _rotateMapWithHeading;
  double? get homeLat => _homeLat;
  double? get homeLng => _homeLng;
  int get homeRadiusMeters => _homeRadiusMeters;
  bool get hasHome => _homeLat != null && _homeLng != null;
  LatLng? get homeLatLng => hasHome ? LatLng(_homeLat!, _homeLng!) : null;

  MapEngineProvider get activeEngine => _activeEngine;
  MapStyleType get mapStyle => _mapStyle;
  String get googleApiKey => _googleApiKey;
  String get openmapApiKey => _openmapApiKey;
  String get openmapDomain => _openmapDomain;
  String get openmapCustomTileUrl => _openmapCustomTileUrl;
  int get distanceFilter => _distanceFilter;
  bool get showFogOfWar => _showFogOfWar;
  bool get autoCenter => _autoCenter;
  bool get autoStopWhenStationary => _autoStopWhenStationary;
  int get autoStopStationaryMinutes => _autoStopStationaryMinutes;

  String get tileUrl => GoongService().getTileUrl(_mapStyle);

  MapSettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final engineIndex = prefs.getInt('map_engine_provider_v2') ?? 0;
      if (engineIndex >= 0 && engineIndex < MapEngineProvider.values.length) {
        _activeEngine = MapEngineProvider.values[engineIndex];
      }

      final styleIndex = prefs.getInt('map_style_index_v2') ?? 0;
      if (styleIndex >= 0 && styleIndex < MapStyleType.values.length) {
        _mapStyle = MapStyleType.values[styleIndex];
      }

      _googleApiKey = prefs.getString('google_api_key') ?? _googleApiKey;
      _openmapApiKey = prefs.getString('openmap_api_key') ?? _openmapApiKey;
      _openmapDomain = prefs.getString('openmap_domain') ?? _openmapDomain;
      _openmapCustomTileUrl = prefs.getString('openmap_custom_tile_url') ?? _openmapCustomTileUrl;
      _githubUpdateToken = prefs.getString('github_update_token') ?? _githubUpdateToken;
      _distanceFilter = prefs.getInt('distance_filter') ?? 5;
      _showFogOfWar = prefs.getBool('show_fog_of_war') ?? true;
      _autoCenter = prefs.getBool('auto_center') ?? true;
      _autoStopWhenStationary = prefs.getBool('auto_stop_stationary') ?? true;
      _autoStopStationaryMinutes = prefs.getInt('auto_stop_stationary_mins') ?? 15;
      _backgroundAutoTrack = prefs.getBool('background_auto_track') ?? false;
      _autoTrackMinSpeedKmh = prefs.getDouble('auto_track_min_speed_kmh') ?? 12.0;
      _autoTrackMinRangeMeters = prefs.getInt('auto_track_min_range_m') ?? 150;

      _vehicleType = VehicleTypeInfo.fromIndex(prefs.getInt('vehicle_type_index'));
      _vehicleColorValue = prefs.getInt('vehicle_color_value') ?? _vehicleColorValue;
      _rotateMapWithHeading = prefs.getBool('rotate_map_with_heading') ?? true;
      _homeLat = prefs.getDouble('home_lat');
      _homeLng = prefs.getDouble('home_lng');
      final savedRadius = prefs.getInt('home_radius_m');
      final migrated = prefs.getBool('home_radius_v2_migrated') ?? false;
      if (!migrated) {
        _homeRadiusMeters = (savedRadius != null && savedRadius <= 150) ? savedRadius : 50;
        await prefs.setInt('home_radius_m', _homeRadiusMeters);
        await prefs.setBool('home_radius_v2_migrated', true);
      } else {
        _homeRadiusMeters = savedRadius ?? 50;
      }

      GoongService().setGoogleApiKey(_googleApiKey);
      GoongService().setActiveEngine(_activeEngine);
      OpenMapService().setApiKey(_openmapApiKey);
      OpenMapService().setDomain(_openmapDomain);
      OpenMapService().setCustomTileUrl(_openmapCustomTileUrl);

      notifyListeners();
    } catch (_) {}
  }

  Future<void> setActiveEngine(MapEngineProvider engine) async {
    _activeEngine = engine;
    GoongService().setActiveEngine(engine);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('map_engine_provider_v2', engine.index);
  }

  Future<void> setMapStyle(MapStyleType style) async {
    _mapStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('map_style_index_v2', style.index);
  }

  Future<void> updateGoogleApiKey(String key) async {
    _googleApiKey = key.trim();
    GoongService().setGoogleApiKey(_googleApiKey);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_api_key', _googleApiKey);
  }

  Future<void> updateOpenMapConfig({
    required String apiKey,
    required String domain,
    String customTileUrl = '',
  }) async {
    _openmapApiKey = apiKey.trim();
    _openmapDomain = domain.trim();
    _openmapCustomTileUrl = customTileUrl.trim();

    OpenMapService().setApiKey(_openmapApiKey);
    OpenMapService().setDomain(_openmapDomain);
    OpenMapService().setCustomTileUrl(_openmapCustomTileUrl);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openmap_api_key', _openmapApiKey);
    await prefs.setString('openmap_domain', _openmapDomain);
    await prefs.setString('openmap_custom_tile_url', _openmapCustomTileUrl);
  }

  Future<void> setDistanceFilter(int filter) async {
    _distanceFilter = filter;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('distance_filter', filter);
  }

  Future<void> toggleFogOfWar() async {
    _showFogOfWar = !_showFogOfWar;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_fog_of_war', _showFogOfWar);
  }

  Future<void> toggleAutoCenter() async {
    _autoCenter = !_autoCenter;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_center', _autoCenter);
  }

  Future<void> setAutoStopWhenStationary(bool value) async {
    _autoStopWhenStationary = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_stop_stationary', value);
  }

  Future<void> setAutoStopStationaryMinutes(int minutes) async {
    _autoStopStationaryMinutes = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_stop_stationary_mins', minutes);
  }

  Future<void> setBackgroundAutoTrack(bool value) async {
    _backgroundAutoTrack = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_auto_track', value);
  }

  Future<void> setAutoTrackMinSpeedKmh(double kmh) async {
    _autoTrackMinSpeedKmh = kmh;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('auto_track_min_speed_kmh', kmh);
  }

  Future<void> setAutoTrackMinRangeMeters(int meters) async {
    _autoTrackMinRangeMeters = meters;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_track_min_range_m', meters);
  }

  Future<void> setVehicleType(VehicleType type) async {
    _vehicleType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vehicle_type_index', type.index);
  }

  Future<void> setVehicleColor(Color color) async {
    _vehicleColorValue = color.toARGB32();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vehicle_color_value', _vehicleColorValue);
  }

  Future<void> setRotateMapWithHeading(bool value) async {
    _rotateMapWithHeading = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rotate_map_with_heading', value);
  }

  Future<void> setHome(double lat, double lng) async {
    _homeLat = lat;
    _homeLng = lng;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('home_lat', lat);
    await prefs.setDouble('home_lng', lng);
  }

  Future<void> clearHome() async {
    _homeLat = null;
    _homeLng = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('home_lat');
    await prefs.remove('home_lng');
  }

  Future<void> setHomeRadius(int meters) async {
    _homeRadiusMeters = meters;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('home_radius_m', meters);
  }

  Future<void> setGithubUpdateToken(String token) async {
    _githubUpdateToken = token.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_githubUpdateToken.isEmpty) {
      await prefs.remove('github_update_token');
    } else {
      await prefs.setString('github_update_token', _githubUpdateToken);
    }
  }
}
