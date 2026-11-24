import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Check and request location permissions and notification permission
  Future<bool> handleLocationPermission() async {
    // Explicitly request notification permission so Foreground Service shows notification in Android 13+
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get cached last known position safely without prompting permissions
  Future<Position?> getLastKnownPosition() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {}
    return null;
  }

  /// Get current one-shot device position
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await handleLocationPermission();
    if (!hasPermission) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  /// Start streaming position updates
  Stream<Position> getPositionStream({int distanceFilter = 5}) {
    late LocationSettings locationSettings;

    // Use high accuracy settings with distance filter
    locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Đang ghi lại hành trình khám phá của bạn...",
        notificationTitle: "Bản Đồ Hành Trình đang hoạt động",
        enableWakeLock: true,
      ),
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Lightweight foreground-only stream used while NOT recording,
  /// so the map can keep showing live position without a persistent notification.
  Stream<Position> getIdlePositionStream({int distanceFilter = 8}) {
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      intervalDuration: const Duration(seconds: 3),
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Battery-conscious background standby stream via Android Foreground Service.
  /// Keeps listening even when screen is off or app is minimized, so
  /// AutoTripDetector can automatically start recording when rapid large-range
  /// movement begins.
  Stream<Position> getBackgroundMonitorStream() {
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 12,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Bản Đồ Hành Trình • Đang canh gác ngầm',
        notificationText: 'Tự động ghi hành trình khi bạn di chuyển tốc độ cao',
        enableWakeLock: false,
      ),
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Ensure location, notification, and (if available) background location
  /// permissions are granted when enabling background auto-tracking.
  Future<bool> requestBackgroundMonitorPermission() async {
    final baseGranted = await handleLocationPermission();
    if (!baseGranted) return false;
    try {
      if (await Permission.locationAlways.isDenied) {
        await Permission.locationAlways.request();
      }
    } catch (_) {}
    return true;
  }

  /// Whether location permission is already granted (does not prompt).
  Future<bool> hasPermissionWithoutPrompt() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Request notification permission silently in the background (Android 13+)
  void requestNotificationPermissionAsync() {
    try {
      Permission.notification.status.then((status) {
        if (status.isDenied) {
          Permission.notification.request();
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  /// Request only location permission at app launch (no notification prompt).
  Future<bool> requestLocationPermissionOnly() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Calculate distance between two points in meters
  static double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
}
