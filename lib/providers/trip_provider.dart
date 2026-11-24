import 'package:flutter/foundation.dart';
import '../models/monthly_stats.dart';
import '../models/pinned_place.dart';
import '../models/province_stats.dart';
import '../models/track_point.dart';
import '../models/trip.dart';
import '../models/waypoint.dart';
import '../services/database_service.dart';
import '../services/exploration_calculator.dart';

class TripProvider with ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<Trip> _trips = [];
  Map<String, List<TrackPoint>> _allExplorationRoutes = {};
  List<Waypoint> _allWaypoints = [];
  List<PinnedPlace> _pinnedPlaces = [];
  MonthlyStats? _currentMonthlyStats;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _isLoading = false;
  double _uniqueExploredKm = 0.0;

  List<Trip> get trips => _trips;
  Map<String, List<TrackPoint>> get allExplorationRoutes => _allExplorationRoutes;
  List<Waypoint> get allWaypoints => _allWaypoints;
  List<PinnedPlace> get pinnedPlaces => List.unmodifiable(_pinnedPlaces);
  List<Waypoint> get photoWaypoints => _allWaypoints.where((w) => w.hasPhoto).toList();
  MonthlyStats? get currentMonthlyStats => _currentMonthlyStats;
  int get selectedYear => _selectedYear;
  int get selectedMonth => _selectedMonth;
  bool get isLoading => _isLoading;

  /// True deduplicated kilometers explored across all trips (each road segment counted once)
  double get uniqueExploredKm => _uniqueExploredKm;

  /// Alias for unique explored km so existing UI/badges automatically reflect real unique exploration
  double get totalExploredKm => _uniqueExploredKm;

  /// Raw sum of traveled kilometers across every recorded trip (including repeated roads)
  double get totalTraveledKm {
    return _trips.fold(0.0, (sum, trip) => sum + trip.distanceKm);
  }

  /// Total exploration hours
  double get totalExploredHours {
    final totalSec = _trips.fold(0, (sum, trip) => sum + trip.durationSeconds);
    return totalSec / 3600.0;
  }

  /// Number of provinces/cities in Vietnam with at least one recorded exploration
  int get exploredProvinceCount {
    return getProvinceRankings().where((p) => p.distanceKm > 0 || p.tripCount > 0).length;
  }

  // Per-province aggregates computed along the FULL route of every trip
  // (every province crossed counts, not only the start/end province).
  Map<String, double> _provinceNewKm = {};
  Map<String, double> _provinceTraveledKm = {};
  Map<String, int> _provinceTripCount = {};
  List<ProvinceStats>? _cachedRankings;

  /// Minimum distance driven inside a province for the trip to count as
  /// having passed through it (filters GPS noise right on a border).
  static const double minProvincePassMeters = 300.0;

  /// Real traveled km inside each province (including repeated roads).
  Map<String, double> get provinceTraveledKm => Map.unmodifiable(_provinceTraveledKm);

  void _rebuildProvinceAggregates(ExplorationSummary summary) {
    final Map<String, double> newKm = {};
    final Map<String, double> traveledKm = {};
    final Map<String, int> tripCount = {};

    for (final trip in _trips) {
      final traveled = summary.traveledMetersByTripProvince[trip.id] ?? const {};
      final fresh = summary.newMetersByTripProvince[trip.id] ?? const {};
      final totalTraveled = traveled.values.fold(0.0, (a, b) => a + b);

      traveled.forEach((province, meters) {
        traveledKm[province] = (traveledKm[province] ?? 0.0) + meters / 1000.0;
        // Count the province if the trip really drove through it, or when the
        // whole trip is tiny (short trips still mark their start/end province).
        if (meters >= minProvincePassMeters || totalTraveled < minProvincePassMeters * 2) {
          tripCount[province] = (tripCount[province] ?? 0) + 1;
        }
      });
      fresh.forEach((province, meters) {
        newKm[province] = (newKm[province] ?? 0.0) + meters / 1000.0;
      });
    }

    _provinceNewKm = newKm;
    _provinceTraveledKm = traveledKm;
    _provinceTripCount = tripCount;
    _cachedRankings = null;
  }

  /// Get personal exploration statistics ranked across Vietnam's 63 provinces
  List<ProvinceStats> getProvinceRankings() {
    final cached = _cachedRankings;
    if (cached != null) return cached;

    final Map<String, int> waypointMap = {};
    for (final wp in _allWaypoints) {
      final province = VietnamProvinces.matchProvince(wp.latitude, wp.longitude, '${wp.name} ${wp.note ?? ''}');
      waypointMap[province] = (waypointMap[province] ?? 0) + 1;
    }

    // Build list across all 63 provinces
    final List<ProvinceStats> list = [];
    for (final p in VietnamProvinces.allProvinces) {
      list.add(ProvinceStats(
        provinceName: p,
        distanceKm: _provinceNewKm[p] ?? 0.0,
        traveledKm: _provinceTraveledKm[p] ?? 0.0,
        tripCount: _provinceTripCount[p] ?? 0,
        waypointCount: waypointMap[p] ?? 0,
      ));
    }

    // Sort by distance descending, then by trip count
    list.sort((a, b) {
      final aDist = a.distanceKm > 0 ? a.distanceKm : a.traveledKm;
      final bDist = b.distanceKm > 0 ? b.distanceKm : b.traveledKm;
      final cmp = bDist.compareTo(aDist);
      if (cmp != 0) return cmp;
      final tripCmp = b.tripCount.compareTo(a.tripCount);
      if (tripCmp != 0) return tripCmp;
      return a.provinceName.compareTo(b.provinceName);
    });

    final List<ProvinceStats> rankedList = [];
    for (int i = 0; i < list.length; i++) {
      rankedList.add(ProvinceStats(
        provinceName: list[i].provinceName,
        distanceKm: list[i].distanceKm,
        traveledKm: list[i].traveledKm,
        tripCount: list[i].tripCount,
        waypointCount: list[i].waypointCount,
        rank: i + 1,
      ));
    }

    _cachedRankings = rankedList;
    return rankedList;
  }

  TripProvider() {
    refreshAll();
  }

  Future<void> refreshAll() async {
    _isLoading = true;
    notifyListeners();

    await loadTrips();
    await loadExplorationData();
    await _recomputeExplorationMetrics();
    await loadMonthlyStats(_selectedYear, _selectedMonth);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _recomputeExplorationMetrics() async {
    final summary = ExplorationCalculator.computeSummary(_trips, _allExplorationRoutes);
    _uniqueExploredKm = summary.totalUniqueExploredMeters / 1000.0;
    _rebuildProvinceAggregates(summary);

    final Map<String, double> dirtyUpdates = {};
    for (final trip in _trips) {
      final computedNew = summary.newMetersByTripId[trip.id] ?? trip.totalDistance;
      if ((trip.newDistance - computedNew).abs() > 0.5) {
        trip.newDistance = computedNew;
        dirtyUpdates[trip.id] = computedNew;
      }
    }

    if (dirtyUpdates.isNotEmpty) {
      await _dbService.updateTripsNewDistancesBatch(dirtyUpdates);
    }
  }

  Future<void> loadTrips() async {
    _trips = await _dbService.getAllTrips();
    notifyListeners();
  }

  Future<void> loadExplorationData() async {
    _allExplorationRoutes = await _dbService.getAllExploredRoutes();
    _allWaypoints = await _dbService.getAllWaypoints();
    _pinnedPlaces = await _dbService.getAllPinnedPlaces();
    notifyListeners();
  }

  Future<void> loadPinnedPlaces() async {
    _pinnedPlaces = await _dbService.getAllPinnedPlaces();
    notifyListeners();
  }

  Future<void> addPinnedPlace(PinnedPlace place) async {
    await _dbService.insertPinnedPlace(place);
    await loadPinnedPlaces();
  }

  Future<void> updatePinnedPlace(PinnedPlace place) async {
    await _dbService.updatePinnedPlace(place);
    await loadPinnedPlaces();
  }

  Future<void> deletePinnedPlace(String id) async {
    await _dbService.deletePinnedPlace(id);
    await loadPinnedPlaces();
  }

  Future<void> deleteWaypoint(String id) async {
    await _dbService.deleteWaypoint(id);
    await refreshAll();
  }

  Future<void> loadMonthlyStats(int year, int month) async {
    _selectedYear = year;
    _selectedMonth = month;
    final monthTrips = _trips
        .where((t) => t.startTime.year == year && t.startTime.month == month)
        .toList();
    final waypointCount = await _dbService.getWaypointCountForMonth(year, month);
    _currentMonthlyStats = MonthlyStats.calculate(year, month, monthTrips, waypointCount);
    notifyListeners();
  }

  void nextMonth() {
    if (_selectedMonth == 12) {
      _selectedYear++;
      _selectedMonth = 1;
    } else {
      _selectedMonth++;
    }
    loadMonthlyStats(_selectedYear, _selectedMonth);
  }

  void previousMonth() {
    if (_selectedMonth == 1) {
      _selectedYear--;
      _selectedMonth = 12;
    } else {
      _selectedMonth--;
    }
    loadMonthlyStats(_selectedYear, _selectedMonth);
  }

  Future<void> deleteTrip(String tripId) async {
    await _dbService.deleteTrip(tripId);
    await refreshAll();
  }

  Future<void> updateTripTitle(String tripId, String newTitle) async {
    final trip = await _dbService.getTrip(tripId);
    if (trip != null) {
      trip.title = newTitle;
      await _dbService.updateTrip(trip);
      await refreshAll();
    }
  }

  Future<void> clearAllData() async {
    _isLoading = true;
    notifyListeners();
    await _dbService.clearAllData();
    await refreshAll();
  }

  /// Import and restore full database from JSON backup structure
  Future<bool> importBackupJson(Map<String, dynamic> data) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _dbService.importDatabaseJson(data);
      await refreshAll();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
