import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/pinned_place.dart';
import '../models/stay_point.dart';
import '../models/track_point.dart';
import '../models/trip.dart';
import '../models/vehicle_type.dart';
import '../models/waypoint.dart';
import '../services/auto_trip_detector.dart';
import '../services/database_service.dart';
import '../services/exploration_calculator.dart';
import '../services/goong_service.dart';
import '../services/location_service.dart';

class TrackingProvider with ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locationService = LocationService();
  final GoongService _goongService = GoongService();

  bool _isStarting = false;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isAutoStopping = false;
  Trip? _currentTrip;
  final List<TrackPoint> _currentPoints = [];
  final List<Waypoint> _currentWaypoints = [];
  Position? _currentPosition;
  double _currentSpeedKmh = 0.0;
  double _currentDistanceMeters = 0.0;
  double _currentNewDistanceMeters = 0.0;
  int _elapsedSeconds = 0;
  double _maxSpeed = 0.0; // m/s
  VehicleType _currentVehicleType = VehicleType.motorbike;
  LiveExplorationTracker? _liveExplorer;

  Timer? _timer;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<Position>? _idleSubscription;
  StreamSubscription<Position>? _backgroundMonitorSubscription;

  // Background auto-start monitoring state
  bool _backgroundMonitoringEnabled = false;
  bool _isBackgroundMonitoringActive = false;
  final AutoTripDetector _autoTripDetector = AutoTripDetector();
  int _recordingDistanceFilter = 5;
  Map<String, List<TrackPoint>> _cachedPriorRoutes = {};
  String? lastAutoStartedMessage;
  VoidCallback? onTripCompletedCallback;

  // Movement direction (GPS course over ground, degrees from north)
  double? _courseHeading;
  bool _hasLiveFix = false;

  // Home ("Nhà") & custom pinned places detection
  double? _homeLat;
  double? _homeLng;
  int _homeRadiusMeters = 50;
  List<PinnedPlace> _pinnedPlaces = [];
  bool _startAddressResolved = false;

  /// Label stored as trip start/end address when it begins/ends near home.
  static const String homeAddressLabel = 'Nhà';

  // Auto-detect stay/stop point variables
  DateTime? _stayCandidateStartTime;
  DateTime? _lastSignificantMovementTime;
  Position? _stayCandidatePosition;
  bool _stayRecordedForCurrentStop = false;
  final List<StayPoint> _pendingStayPoints = [];

  // Auto-stop when stationary too long
  bool autoStopWhenStationary = true;
  int autoStopMinutes = 15;
  String? lastAutoStoppedMessage;

  // Getters
  bool get isStarting => _isStarting;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get backgroundMonitoringEnabled => _backgroundMonitoringEnabled;
  bool get isBackgroundMonitoringActive => _isBackgroundMonitoringActive;
  double get autoTrackMinSpeedKmh => _autoTripDetector.minSpeedKmh;
  int get autoTrackMinRangeMeters => _autoTripDetector.minRangeMeters;
  Trip? get currentTrip => _currentTrip;
  List<TrackPoint> get currentPoints => List.unmodifiable(_currentPoints);
  List<Waypoint> get currentWaypoints => List.unmodifiable(_currentWaypoints);
  List<StayPoint> get pendingStayPoints => List.unmodifiable(_pendingStayPoints);
  Position? get currentPosition => _currentPosition;
  double get currentSpeedKmh => _currentSpeedKmh;
  double get currentDistanceMeters => _currentDistanceMeters;
  double get currentDistanceKm => _currentDistanceMeters / 1000.0;
  double get currentNewDistanceMeters => _currentNewDistanceMeters;
  double get currentNewDistanceKm => _currentNewDistanceMeters / 1000.0;
  int get elapsedSeconds => _elapsedSeconds;
  double get maxSpeedKmh => _maxSpeed * 3.6;
  double? get courseHeading => _courseHeading;
  bool get hasLiveFix => _hasLiveFix;
  VehicleType get currentVehicleType => _currentVehicleType;

  /// Updates the active vehicle type. If a journey is currently recording,
  /// records the vehicle switch so all subsequent points carry the new vehicle!
  Future<void> setCurrentVehicleType(VehicleType type) async {
    if (_currentVehicleType == type) return;
    _currentVehicleType = type;

    if (_isRecording && _currentTrip != null) {
      _currentTrip!.recordVehicleSwitch(type);
      if (_currentPosition != null) {
        final switchPt = TrackPoint(
          tripId: _currentTrip!.id,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          altitude: _currentPosition!.altitude,
          speed: _currentPosition!.speed,
          accuracy: _currentPosition!.accuracy,
          timestamp: DateTime.now(),
          vehicleType: type,
        );
        _currentPoints.add(switchPt);
        _currentTrip!.pointCount = _currentPoints.length;
        await _dbService.insertTrackPoint(switchPt);
      }
      await _dbService.updateTrip(_currentTrip!);
    }
    notifyListeners();
  }

  /// Whether a coordinate lies within [radiusMeters] of the home pin.
  static bool isNearHome(
    double lat,
    double lng, {
    required double? homeLat,
    required double? homeLng,
    int radiusMeters = 50,
  }) {
    if (homeLat == null || homeLng == null) return false;
    final d = LocationService.calculateDistance(lat, lng, homeLat, homeLng);
    return d <= radiusMeters;
  }

  /// Update the home pin used for start/end detection.
  void setHomeConfig({double? lat, double? lng, int radiusMeters = 50}) {
    _homeLat = lat;
    _homeLng = lng;
    _homeRadiusMeters = radiusMeters;
  }

  /// Update the list of user-pinned places (work, school, cafe, etc.) used for start/end recognition.
  void setPinnedPlaces(List<PinnedPlace> places) {
    _pinnedPlaces = List.unmodifiable(places);
  }

  /// Returns `'Nhà'` if within Home radius, or the closest matching [PinnedPlace.name]
  /// if within its detection radius, or `null` otherwise.
  String? findMatchingPinnedPlaceLabel(double lat, double lng) {
    if (isNearHome(
      lat,
      lng,
      homeLat: _homeLat,
      homeLng: _homeLng,
      radiusMeters: _homeRadiusMeters,
    )) {
      return homeAddressLabel;
    }

    PinnedPlace? best;
    double bestDist = double.infinity;
    for (final place in _pinnedPlaces) {
      final d = LocationService.calculateDistance(lat, lng, place.latitude, place.longitude);
      if (d <= place.radiusMeters && d < bestDist) {
        best = place;
        bestDist = d;
      }
    }
    return best?.name;
  }

  double get avgSpeedKmh {
    if (_elapsedSeconds <= 0 || _currentDistanceMeters <= 0) return 0.0;
    final hours = _elapsedSeconds / 3600.0;
    return _currentDistanceMeters / 1000.0 / hours;
  }

  String get formattedDuration {
    final hours = _elapsedSeconds ~/ 3600;
    final minutes = (_elapsedSeconds % 3600) ~/ 60;
    final seconds = _elapsedSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  TrackingProvider() {
    initInitialLocation();
    loadPendingStayPoints();
  }

  /// Load pending unconfirmed stay points from SQLite safely
  Future<void> loadPendingStayPoints() async {
    try {
      final list = await _dbService.getPendingStayPoints();
      _pendingStayPoints.clear();
      _pendingStayPoints.addAll(list);
      notifyListeners();
    } catch (_) {}
  }

  /// On app launch: show last known spot instantly, then request permission,
  /// read the precise current location and keep a light live stream while idle.
  Future<void> initInitialLocation() async {
    try {
      final pos = await _locationService.getLastKnownPosition();
      if (pos != null && _currentPosition == null) {
        _currentPosition = pos;
        notifyListeners();
      }
    } catch (_) {}

    try {
      final granted = await _locationService.requestLocationPermissionOnly();
      if (!granted) return;

      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!_isRecording) {
        _currentPosition = current;
        _hasLiveFix = true;
        _updateCourse(current);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Fetches a single fresh GPS position on demand (e.g. when tapping Recenter while idle)
  /// without keeping a continuous GPS stream running, saving battery when not recording.
  Future<Position?> refreshCurrentLocationOnce() async {
    if (_isRecording) return _currentPosition;
    try {
      final ok = await _locationService.hasPermissionWithoutPrompt();
      if (!ok) return _currentPosition;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _currentPosition = pos;
      _hasLiveFix = true;
      _updateCourse(pos);
      notifyListeners();
      return pos;
    } catch (_) {
      return _currentPosition;
    }
  }

  void _startIdleStream() {
    // Intentionally kept off when idle to conserve battery; distance & tracking
    // only run when a journey is actively recording (or background monitor is enabled).
    _stopIdleStream();
  }

  void _stopIdleStream() {
    _idleSubscription?.cancel();
    _idleSubscription = null;
  }

  /// Syncs background auto-tracking, home/pinned places, vehicle, and auto-stop settings.
  Future<void> configureBackgroundMonitoring({
    required bool enabled,
    required double minSpeedKmh,
    required int minRangeMeters,
    required bool autoStop,
    required int autoStopMins,
    required int distanceFilter,
    VehicleType? vehicleType,
    double? homeLat,
    double? homeLng,
    int homeRadiusMeters = 50,
    List<PinnedPlace>? pinnedPlaces,
    Map<String, List<TrackPoint>>? priorRoutes,
  }) async {
    autoStopWhenStationary = autoStop;
    autoStopMinutes = autoStopMins;
    _recordingDistanceFilter = distanceFilter;
    if (vehicleType != null && !_isRecording) {
      _currentVehicleType = vehicleType;
    }
    _autoTripDetector.updateThresholds(
      minSpeedKmh: minSpeedKmh,
      minRangeMeters: minRangeMeters,
    );
    setHomeConfig(lat: homeLat, lng: homeLng, radiusMeters: homeRadiusMeters);
    if (pinnedPlaces != null) {
      setPinnedPlaces(pinnedPlaces);
    }
    if (priorRoutes != null) {
      _cachedPriorRoutes = priorRoutes;
    }

    final wasEnabled = _backgroundMonitoringEnabled;
    _backgroundMonitoringEnabled = enabled;

    if (enabled && !_isRecording && !_isBackgroundMonitoringActive) {
      await _startBackgroundMonitorStream();
    } else if (!enabled && (wasEnabled || _isBackgroundMonitoringActive)) {
      _stopBackgroundMonitorStream();
      if (!_isRecording) {
        _startIdleStream();
      }
      notifyListeners();
    }
  }

  Future<void> _startBackgroundMonitorStream() async {
    if (_isRecording || !_backgroundMonitoringEnabled) return;
    if (_backgroundMonitorSubscription != null) return;

    final ok = await _locationService.hasPermissionWithoutPrompt();
    if (!ok) {
      final granted = await _locationService.requestBackgroundMonitorPermission();
      if (!granted) {
        _isBackgroundMonitoringActive = false;
        notifyListeners();
        return;
      }
    } else {
      _locationService.requestNotificationPermissionAsync();
    }

    _stopIdleStream();
    _autoTripDetector.reset();
    if (_currentPosition != null) {
      _autoTripDetector.evaluate(AutoTripSample.fromPosition(_currentPosition!));
    }

    _isBackgroundMonitoringActive = true;
    _backgroundMonitorSubscription =
        _locationService.getBackgroundMonitorStream().listen(
      (pos) {
        if (_isRecording || !_backgroundMonitoringEnabled) return;
        _currentPosition = pos;
        _hasLiveFix = true;
        _updateCourse(pos);

        final res = _autoTripDetector.evaluate(AutoTripSample.fromPosition(pos));
        if (res.triggered) {
          _autoStartFromSamples(res.departureSamples);
        } else {
          notifyListeners();
        }
      },
      onError: (_) {
        _isBackgroundMonitoringActive = false;
        _backgroundMonitorSubscription = null;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void _stopBackgroundMonitorStream() {
    _backgroundMonitorSubscription?.cancel();
    _backgroundMonitorSubscription = null;
    _isBackgroundMonitoringActive = false;
    _autoTripDetector.reset();
  }

  void _updateCourse(Position pos) {
    // GPS course is only meaningful while actually moving (> ~3.6 km/h)
    if (pos.speed > 1.0 && pos.heading >= 0) {
      _courseHeading = pos.heading;
    }
  }

  /// Resolve start address: matching pinned place ("Nhà", "Công ty", ...), otherwise reverse geocode.
  void _resolveStartAddressLatLng(double lat, double lng) {
    if (_startAddressResolved || _currentTrip == null) return;
    _startAddressResolved = true;

    final pinnedLabel = findMatchingPinnedPlaceLabel(lat, lng);
    if (pinnedLabel != null) {
      _currentTrip!.startAddress = pinnedLabel;
      _currentTrip!.title =
          'Xuất phát từ $pinnedLabel • ${DateFormat('dd/MM/yyyy HH:mm').format(_currentTrip!.startTime)}';
      _dbService.updateTrip(_currentTrip!);
      notifyListeners();
      return;
    }

    _goongService.reverseGeocode(lat, lng).then((addr) {
      if (addr != null && _currentTrip != null) {
        _currentTrip!.startAddress = addr;
        _dbService.updateTrip(_currentTrip!);
        notifyListeners();
      }
    });
  }

  void _resolveStartAddress(Position pos) {
    _resolveStartAddressLatLng(pos.latitude, pos.longitude);
  }

  /// Automatically starts a trip from buffered departure samples detected in background standby.
  Future<void> _autoStartFromSamples(List<AutoTripSample> samples) async {
    if (_isStarting || _isRecording || samples.isEmpty) return;
    _isStarting = true;

    try {
      _stopBackgroundMonitorStream();
      _stopIdleStream();
      lastAutoStoppedMessage = null;
      lastAutoStartedMessage =
          'Đã tự động ghi hành trình mới khi bạn di chuyển nhanh phạm vi lớn!';

      final first = samples.first;
      final tripId = const Uuid().v4();
      final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(first.timestamp);

      _currentTrip = Trip(
        id: tripId,
        title: 'Khám phá $formattedDate',
        startTime: first.timestamp,
        totalDistance: 0.0,
        durationSeconds: 0,
        maxSpeed: 0.0,
        avgSpeed: 0.0,
        pointCount: 0,
        isCompleted: false,
        vehicleType: _currentVehicleType,
        vehicleTypesUsed: [_currentVehicleType],
      );

      _currentPoints.clear();
      _currentWaypoints.clear();
      _currentDistanceMeters = 0.0;
      _currentNewDistanceMeters = 0.0;
      _currentSpeedKmh = samples.last.speedMps > 0 ? samples.last.speedMps * 3.6 : 0.0;
      _maxSpeed = 0.0;
      _elapsedSeconds = DateTime.now()
          .difference(first.timestamp)
          .inSeconds
          .clamp(0, 3600);
      _isRecording = true;
      _isPaused = false;
      _isAutoStopping = false;
      _stayCandidateStartTime = null;
      _lastSignificantMovementTime = DateTime.now();
      _stayCandidatePosition = null;
      _stayRecordedForCurrentStop = false;
      _startAddressResolved = false;

      final tracker = LiveExplorationTracker();
      if (_cachedPriorRoutes.isNotEmpty) {
        tracker.seedFromRoutes(_cachedPriorRoutes, excludeTripId: tripId);
      }
      _liveExplorer = tracker;

      await _dbService.insertTrip(_currentTrip!);

      // Backfill all departure samples so starting pin ("Nhà"/"Công ty") & initial leg are preserved
      final List<TrackPoint> batchPts = [];
      for (final s in samples) {
        if (s.speedMps > _maxSpeed) {
          _maxSpeed = s.speedMps;
        }
        if (batchPts.isNotEmpty) {
          final prev = batchPts.last;
          final dist = LocationService.calculateDistance(
            prev.latitude,
            prev.longitude,
            s.latitude,
            s.longitude,
          );
          if (dist >= 1.0 && dist < 500.0) {
            _currentDistanceMeters += dist;
          }
        }
        final tp = TrackPoint(
          tripId: tripId,
          latitude: s.latitude,
          longitude: s.longitude,
          altitude: s.altitude,
          speed: s.speedMps,
          accuracy: s.accuracyMeters,
          timestamp: s.timestamp,
          vehicleType: _currentVehicleType,
        );
        batchPts.add(tp);
        _currentPoints.add(tp);
        final rawNew = tracker.addPoint(s.latitude, s.longitude);
        _currentNewDistanceMeters = rawNew.clamp(0.0, _currentDistanceMeters);
      }

      _currentTrip!.pointCount = _currentPoints.length;
      _currentTrip!.totalDistance = _currentDistanceMeters;
      _currentTrip!.newDistance = _currentNewDistanceMeters;
      _currentTrip!.maxSpeed = _maxSpeed;
      _currentTrip!.avgSpeed = avgSpeedKmh / 3.6;

      await _dbService.insertTrackPointsBatch(batchPts);
      await _dbService.updateTrip(_currentTrip!);
      _resolveStartAddressLatLng(first.latitude, first.longitude);

      _startRecordingTimer();

      _positionSubscription?.cancel();
      _positionSubscription = _locationService
          .getPositionStream(distanceFilter: _recordingDistanceFilter)
          .listen((position) {
        if (!_isPaused && _isRecording) {
          _onNewPosition(position);
        }
      });

      _isStarting = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error auto-starting trip: $e');
      _isStarting = false;
      _isRecording = false;
      notifyListeners();
    }
  }

  void _startRecordingTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && _isRecording) {
        _elapsedSeconds++;
        _currentTrip?.durationSeconds = _elapsedSeconds;

        // Also check stationary timeout here so auto-stop triggers reliably
        // even when the device is completely still and GPS stops emitting updates!
        if (autoStopWhenStationary && !_isAutoStopping) {
          final refTime = _stayCandidateStartTime ?? _lastSignificantMovementTime;
          if (refTime != null) {
            final idleMins = DateTime.now().difference(refTime).inMinutes;
            if (idleMins >= autoStopMinutes) {
              _autoStopForStationaryDuration(idleMins);
              return;
            }
          }
        }
        notifyListeners();
      }
    });
  }

  void dismissAutoStartMessage() {
    lastAutoStartedMessage = null;
    notifyListeners();
  }

  /// Start a new journey recording instantly with zero delay
  Future<bool> startTracking({
    int distanceFilter = 5,
    bool autoStop = true,
    int autoStopMins = 15,
    double? homeLat,
    double? homeLng,
    int homeRadiusMeters = 50,
    VehicleType? vehicleType,
    Map<String, List<TrackPoint>>? priorRoutes,
  }) async {
    if (_isStarting || _isRecording) return false;
    _isStarting = true;
    notifyListeners();

    try {
      autoStopWhenStationary = autoStop;
      autoStopMinutes = autoStopMins;
      _recordingDistanceFilter = distanceFilter;
      if (vehicleType != null) {
        _currentVehicleType = vehicleType;
      }
      lastAutoStoppedMessage = null;
      lastAutoStartedMessage = null;
      setHomeConfig(lat: homeLat, lng: homeLng, radiusMeters: homeRadiusMeters);
      if (priorRoutes != null) {
        _cachedPriorRoutes = priorRoutes;
      }

      // Fast permission check (< 2ms) without re-prompting if already granted
      bool hasPermission = await _locationService.hasPermissionWithoutPrompt();
      if (!hasPermission) {
        hasPermission = await _locationService.handleLocationPermission();
        if (!hasPermission) {
          _isStarting = false;
          notifyListeners();
          return false;
        }
      } else {
        // Request notification permission silently in background on Android 13+
        _locationService.requestNotificationPermissionAsync();
      }

      _stopBackgroundMonitorStream();
      _stopIdleStream();

      // INSTANT position resolution:
      // 1. Use existing in-memory position (0ms)
      // 2. If null, use the OS cached last known position (< 5ms)
      // Never block on Geolocator.getCurrentPosition() which takes 3-8s for satellite lock!
      if (_currentPosition == null) {
        final cached = await _locationService.getLastKnownPosition();
        if (cached != null) {
          _currentPosition = cached;
        }
      }

      final now = DateTime.now();
      final tripId = const Uuid().v4();
      final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);

      _currentTrip = Trip(
        id: tripId,
        title: 'Khám phá $formattedDate',
        startTime: now,
        totalDistance: 0.0,
        durationSeconds: 0,
        maxSpeed: 0.0,
        avgSpeed: 0.0,
        pointCount: 0,
        isCompleted: false,
        vehicleType: _currentVehicleType,
        vehicleTypesUsed: [_currentVehicleType],
      );

      _currentPoints.clear();
      _currentWaypoints.clear();
      _currentDistanceMeters = 0.0;
      _currentNewDistanceMeters = 0.0;
      _currentSpeedKmh = 0.0;
      _maxSpeed = 0.0;
      _elapsedSeconds = 0;
      _isRecording = true;
      _isPaused = false;
      _isAutoStopping = false;
      _stayCandidateStartTime = null;
      _lastSignificantMovementTime = DateTime.now();
      _stayCandidatePosition = null;
      _stayRecordedForCurrentStop = false;
      _startAddressResolved = false;

      final tracker = LiveExplorationTracker();
      if (priorRoutes != null && priorRoutes.isNotEmpty) {
        tracker.seedFromRoutes(priorRoutes, excludeTripId: tripId);
      } else if (priorRoutes == null) {
        // Fallback async seed if caller did not pass preloaded routes
        _dbService.getAllExploredRoutes().then((routes) {
          if (_liveExplorer == tracker && routes.isNotEmpty) {
            final rebuilt = LiveExplorationTracker()
              ..seedFromRoutes(routes, excludeTripId: tripId);
            for (final pt in _currentPoints) {
              rebuilt.addPoint(pt.latitude, pt.longitude);
            }
            _liveExplorer = rebuilt;
            _currentNewDistanceMeters = rebuilt.newMeters.clamp(0.0, _currentDistanceMeters);
            _currentTrip?.newDistance = _currentNewDistanceMeters;
            notifyListeners();
          }
        }).catchError((_) {});
      }
      _liveExplorer = tracker;

      // Start elapsed timer immediately (also monitors stationary auto-stop)
      _startRecordingTimer();

      // Save initial trip to SQLite first (~2ms) so foreign key constraints are met
      await _dbService.insertTrip(_currentTrip!);

      // If we have an initial position, add it as first track point right away
      if (_currentPosition != null) {
        _addPointFromPosition(_currentPosition!);
        _resolveStartAddress(_currentPosition!);
      }

      // Subscribe to continuous location updates immediately
      _positionSubscription?.cancel();
      _positionSubscription = _locationService
          .getPositionStream(distanceFilter: distanceFilter)
          .listen((position) {
        if (!_isPaused && _isRecording) {
          _onNewPosition(position);
        }
      });

      _isStarting = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error starting tracking: $e');
      _isStarting = false;
      _isRecording = false;
      notifyListeners();
      return false;
    }
  }

  void _onNewPosition(Position position) {
    _currentPosition = position;
    _hasLiveFix = true;
    _updateCourse(position);
    _resolveStartAddress(position);
    _currentSpeedKmh = position.speed > 0 ? (position.speed * 3.6) : 0.0;

    if (position.speed > _maxSpeed) {
      _maxSpeed = position.speed;
      _currentTrip?.maxSpeed = _maxSpeed;
    }

    if (_currentPoints.isNotEmpty) {
      final lastPoint = _currentPoints.last;
      final dist = LocationService.calculateDistance(
        lastPoint.latitude,
        lastPoint.longitude,
        position.latitude,
        position.longitude,
      );

      // Filter out GPS jump noise (>500m in 2 seconds is likely an anomaly)
      if (dist >= 1.0 && dist < 500.0) {
        _currentDistanceMeters += dist;
        _currentTrip?.totalDistance = _currentDistanceMeters;
      }
    }

    _addPointFromPosition(position);

    // --- Automatic Stay/Stop Point Detection ---
    _checkStationaryStop(position);

    notifyListeners();
  }

  void _checkStationaryStop(Position position) {
    if (_currentTrip == null) return;

    // 1.5 m/s (~5.4 km/h): stationary or slow indoor meandering
    final isStationary = position.speed < 1.5;

    if (isStationary) {
      if (_stayCandidateStartTime == null) {
        _stayCandidateStartTime = DateTime.now();
        _stayCandidatePosition = position;
        _stayRecordedForCurrentStop = false;
      } else if (_stayCandidatePosition != null) {
        final dist = LocationService.calculateDistance(
          _stayCandidatePosition!.latitude,
          _stayCandidatePosition!.longitude,
          position.latitude,
          position.longitude,
        );

        if (dist <= 40.0) {
          // Has stayed around the same spot (<= 40m)
          final duration = DateTime.now().difference(_stayCandidateStartTime!);
          // Stop threshold: 2 minutes
          if (duration.inSeconds >= 120 && !_stayRecordedForCurrentStop) {
            _recordAutoStayPoint(_stayCandidatePosition!, _stayCandidateStartTime!);
            _stayRecordedForCurrentStop = true;
          }

          // Auto-stop tracking when stationary too long (e.g. 15 minutes)
          if (autoStopWhenStationary &&
              !_isAutoStopping &&
              duration.inMinutes >= autoStopMinutes) {
            _autoStopForStationaryDuration(duration.inMinutes);
            return;
          }
        } else {
          // Moved to another spot (> 40m away)
          _stayCandidateStartTime = DateTime.now();
          _lastSignificantMovementTime = DateTime.now();
          _stayCandidatePosition = position;
          _stayRecordedForCurrentStop = false;
        }
      }
    } else {
      // Speed >= 1.5 m/s (~5.4 km/h)
      if (_stayCandidatePosition != null) {
        final dist = LocationService.calculateDistance(
          _stayCandidatePosition!.latitude,
          _stayCandidatePosition!.longitude,
          position.latitude,
          position.longitude,
        );
        if (dist > 45.0) {
          _stayCandidateStartTime = null;
          _stayCandidatePosition = null;
          _stayRecordedForCurrentStop = false;
          _lastSignificantMovementTime = DateTime.now();
        }
      } else {
        _lastSignificantMovementTime = DateTime.now();
      }
    }
  }

  Future<void> _recordAutoStayPoint(Position pos, DateTime arrivalTime) async {
    if (_currentTrip == null) return;

    final stayPointId = const Uuid().v4();
    final now = DateTime.now();

    // Reverse geocode address asynchronously
    String? address;
    try {
      address = await _goongService.reverseGeocode(pos.latitude, pos.longitude);
    } catch (_) {}

    final stayPoint = StayPoint(
      id: stayPointId,
      tripId: _currentTrip!.id,
      latitude: pos.latitude,
      longitude: pos.longitude,
      arrivalTime: arrivalTime,
      departureTime: now,
      address: address ?? 'Toạ độ: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
      status: 'pending',
    );

    _pendingStayPoints.add(stayPoint);
    await _dbService.insertStayPoint(stayPoint);
    notifyListeners();
  }

  Future<void> _autoStopForStationaryDuration(int minutes) async {
    if (_isAutoStopping) return;
    _isAutoStopping = true;
    lastAutoStoppedMessage =
        'Đã tự động kết thúc và lưu hành trình do bạn đã dừng lại hơn $minutes phút.';
    await stopTracking();
    _isAutoStopping = false;
    onTripCompletedCallback?.call();
  }

  void dismissAutoStopMessage() {
    lastAutoStoppedMessage = null;
    notifyListeners();
  }

  /// Confirm a pending stay point into a verified Waypoint
  Future<void> confirmStayPoint(
    StayPoint stayPoint,
    String confirmedName, {
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    stayPoint.status = 'confirmed';
    stayPoint.confirmedName = confirmedName;
    stayPoint.note = note;
    await _dbService.updateStayPoint(stayPoint);

    // Create a verified Waypoint
    final waypoint = Waypoint(
      id: const Uuid().v4(),
      tripId: stayPoint.tripId,
      name: confirmedName,
      note: note ?? stayPoint.address,
      latitude: latitude ?? stayPoint.latitude,
      longitude: longitude ?? stayPoint.longitude,
      timestamp: stayPoint.arrivalTime,
    );

    _currentWaypoints.add(waypoint);
    await _dbService.insertWaypoint(waypoint);

    _pendingStayPoints.removeWhere((p) => p.id == stayPoint.id);
    notifyListeners();
  }

  /// Reject / ignore an auto detected stay point
  Future<void> rejectStayPoint(StayPoint stayPoint) async {
    stayPoint.status = 'rejected';
    await _dbService.updateStayPoint(stayPoint);
    _pendingStayPoints.removeWhere((p) => p.id == stayPoint.id);
    notifyListeners();
  }

  /// Adjust location and confirm stay point
  Future<void> adjustStayPoint(StayPoint stayPoint, double newLat, double newLng, String newName, {String? note}) async {
    final waypoint = Waypoint(
      id: const Uuid().v4(),
      tripId: stayPoint.tripId,
      name: newName,
      note: note ?? 'Địa điểm đã điều chỉnh',
      latitude: newLat,
      longitude: newLng,
      timestamp: stayPoint.arrivalTime,
    );

    _currentWaypoints.add(waypoint);
    await _dbService.insertWaypoint(waypoint);

    stayPoint.status = 'confirmed';
    stayPoint.confirmedName = newName;
    await _dbService.updateStayPoint(stayPoint);

    _pendingStayPoints.removeWhere((p) => p.id == stayPoint.id);
    notifyListeners();
  }

  Future<void> _addPointFromPosition(Position pos) async {
    if (_currentTrip == null) return;

    final point = TrackPoint(
      tripId: _currentTrip!.id,
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed,
      accuracy: pos.accuracy,
      timestamp: DateTime.now(),
      vehicleType: _currentVehicleType,
    );

    _currentPoints.add(point);
    if (_liveExplorer != null) {
      final rawNew = _liveExplorer!.addPoint(pos.latitude, pos.longitude);
      _currentNewDistanceMeters = rawNew.clamp(0.0, _currentDistanceMeters);
    }

    _currentTrip!.pointCount = _currentPoints.length;
    _currentTrip!.totalDistance = _currentDistanceMeters;
    _currentTrip!.newDistance = _currentNewDistanceMeters;
    _currentTrip!.avgSpeed = avgSpeedKmh / 3.6;

    // Persist point to SQLite
    await _dbService.insertTrackPoint(point);
    await _dbService.updateTrip(_currentTrip!);
  }

  /// Pause current tracking session
  void pauseTracking() {
    _isPaused = true;
    notifyListeners();
  }

  /// Resume paused session
  void resumeTracking() {
    _isPaused = false;
    notifyListeners();
  }

  /// Add a custom waypoint (Check-in/POI) at selected or current location
  Future<Waypoint?> addWaypoint(
    String name, {
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    if (_currentTrip == null) return null;
    final lat = latitude ?? _currentPosition?.latitude;
    final lng = longitude ?? _currentPosition?.longitude;
    if (lat == null || lng == null) return null;

    final waypoint = Waypoint(
      id: const Uuid().v4(),
      tripId: _currentTrip!.id,
      name: name,
      note: note,
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
    );

    _currentWaypoints.add(waypoint);
    await _dbService.insertWaypoint(waypoint);
    notifyListeners();
    return waypoint;
  }

  /// Stop tracking, finalize trip and save to SQLite
  Future<Trip?> stopTracking() async {
    if (_currentTrip == null) return null;

    _timer?.cancel();
    _timer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _isRecording = false;
    _isPaused = false;

    final completedTrip = _currentTrip!;
    completedTrip.endTime = DateTime.now();
    completedTrip.isCompleted = true;
    completedTrip.totalDistance = _currentDistanceMeters;
    completedTrip.newDistance = _currentNewDistanceMeters.clamp(0.0, _currentDistanceMeters);
    completedTrip.durationSeconds = _elapsedSeconds;
    completedTrip.maxSpeed = _maxSpeed;
    completedTrip.avgSpeed = avgSpeedKmh / 3.6;
    completedTrip.pointCount = _currentPoints.length;
    completedTrip.points = List.from(_currentPoints);
    completedTrip.waypoints = List.from(_currentWaypoints);
    _liveExplorer = null;

    // Resolve end address: matching pinned place ("Nhà", "Công ty", ...), otherwise reverse geocode
    if (_currentPosition != null) {
      final pinnedLabel = findMatchingPinnedPlaceLabel(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      if (pinnedLabel != null) {
        completedTrip.endAddress = pinnedLabel;
      } else {
        try {
          final endAddr = await _goongService.reverseGeocode(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
          if (endAddr != null) {
            completedTrip.endAddress = endAddr;
          }
        } catch (_) {}
      }
    }

    await _dbService.updateTrip(completedTrip);
    _currentTrip = null;
    _currentSpeedKmh = 0.0;

    notifyListeners();
    if (_backgroundMonitoringEnabled) {
      _startBackgroundMonitorStream();
    } else {
      _startIdleStream();
    }
    return completedTrip;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _idleSubscription?.cancel();
    _backgroundMonitorSubscription?.cancel();
    super.dispose();
  }
}
