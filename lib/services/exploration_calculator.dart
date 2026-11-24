import 'dart:collection';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/province_stats.dart';
import '../models/track_point.dart';
import '../models/trip.dart';
import 'location_service.dart';

class _IndexedSeg {
  final double aLat;
  final double aLng;
  final double bLat;
  final double bLng;
  final double endArc;

  const _IndexedSeg({
    required this.aLat,
    required this.aLng,
    required this.bLat,
    required this.bLng,
    required this.endArc,
  });
}

/// Result of classifying a single trip's segments against prior exploration history.
class TripSegmentBreakdown {
  final double newMeters;
  final double repeatedMeters;
  final List<List<LatLng>> newPolylines;
  final List<List<LatLng>> repeatedPolylines;

  const TripSegmentBreakdown({
    required this.newMeters,
    required this.repeatedMeters,
    required this.newPolylines,
    required this.repeatedPolylines,
  });
}

/// Summary of unique explored vs total traveled distances across all trips.
class ExplorationSummary {
  final double totalUniqueExploredMeters;
  final double totalTraveledMeters;
  final Map<String, double> newMetersByTripId;

  /// tripId -> (province -> meters actually traveled inside that province).
  final Map<String, Map<String, double>> traveledMetersByTripProvince;

  /// tripId -> (province -> newly explored (deduplicated) meters in that province).
  final Map<String, Map<String, double>> newMetersByTripProvince;

  const ExplorationSummary({
    required this.totalUniqueExploredMeters,
    required this.totalTraveledMeters,
    required this.newMetersByTripId,
    this.traveledMetersByTripProvince = const {},
    this.newMetersByTripProvince = const {},
  });
}

/// Spatial hash grid index of explored road sub-segments (each <= 20m).
///
/// Guarantees O(1) average lookup per sub-segment to determine whether a
/// newly traversed path lies within [toleranceMeters] (default 25m) of any
/// previously explored road segment — regardless of travel direction, GPS drift,
/// or differing point spacing.
class ExplorationIndex {
  /// Roads within this distance (meters) of an already-explored segment
  /// are treated as the same explored road (not double-counted).
  static const double defaultToleranceMeters = 25.0;

  /// Subdivide long GPS steps into pieces <= this length so partial overlaps
  /// along intersections or shared highways are measured accurately.
  static const double maxSubSegMeters = 20.0;

  /// Trailing arc-length buffer before committing current-trip segments into
  /// the index. 60m ensures sharp 90-degree corners lose 0m while 180-degree
  /// U-turns / return legs along the same road are properly deduplicated.
  static const double lagArcMeters = 60.0;

  /// Filter out GPS jump anomalies (>= 500m between consecutive points),
  /// matching TrackingProvider._onNewPosition.
  static const double maxValidStepMeters = 500.0;

  /// Grid cell size in degrees (~50.0m lat, ~46.0m lng at northern Vietnam).
  /// Since every indexed sub-segment has length <= 20m (half-length <= 10m)
  /// and tolerance is 25m, any matching segment midpoint is within 35m < 46m,
  /// guaranteed to be found inside a 3x3 cell neighborhood.
  static const double _cellSizeDeg = 0.00045;
  static const double _metersPerDegLat = 111132.92;

  final double toleranceMeters;
  final double _toleranceSq;
  final Map<int, List<_IndexedSeg>> _grid = {};

  ExplorationIndex({this.toleranceMeters = defaultToleranceMeters})
      : _toleranceSq = toleranceMeters * toleranceMeters;

  static int _cellCoord(double deg) => (deg / _cellSizeDeg).floor();

  static int _packKey(int cLat, int cLng) {
    // Shift to positive space so hash keys never collide in 64-bit / 53-bit ints.
    return (cLat + 1000000) * 2000000 + (cLng + 1000000);
  }

  void _insertSegment(_IndexedSeg seg) {
    final midLat = (seg.aLat + seg.bLat) * 0.5;
    final midLng = (seg.aLng + seg.bLng) * 0.5;
    final key = _packKey(_cellCoord(midLat), _cellCoord(midLng));
    _grid.putIfAbsent(key, () => []).add(seg);
  }

  /// Fast local equirectangular distance-squared from query point P to segment AB.
  bool isPointNearExplored(double pLat, double pLng) {
    final cLat = _cellCoord(pLat);
    final cLng = _cellCoord(pLng);
    final cosLat = math.cos(pLat * math.pi / 180.0);
    final mPerDegLng = 111412.84 * cosLat;

    for (int dLat = -1; dLat <= 1; dLat++) {
      for (int dLng = -1; dLng <= 1; dLng++) {
        final bucket = _grid[_packKey(cLat + dLat, cLng + dLng)];
        if (bucket == null) continue;

        for (final seg in bucket) {
          final ax = (seg.aLng - pLng) * mPerDegLng;
          final ay = (seg.aLat - pLat) * _metersPerDegLat;
          final bx = (seg.bLng - pLng) * mPerDegLng;
          final by = (seg.bLat - pLat) * _metersPerDegLat;

          final dx = bx - ax;
          final dy = by - ay;
          final lenSq = dx * dx + dy * dy;

          double cx;
          double cy;
          if (lenSq < 1e-6) {
            cx = ax;
            cy = ay;
          } else {
            final t = ((-ax * dx - ay * dy) / lenSq).clamp(0.0, 1.0);
            cx = ax + t * dx;
            cy = ay + t * dy;
          }

          if (cx * cx + cy * cy <= _toleranceSq) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Indexes a completed trip without needing new-distance output.
  void addTripPoints(List<TrackPoint> points) {
    evaluateAndAddTrip(points);
  }

  /// Evaluates newly discovered meters for [points] while committing its segments
  /// into this index (including deduplicating backtracking within the same trip).
  ///
  /// [onSubSegment] (optional) receives every evaluated sub-segment midpoint,
  /// its length in meters and whether it was newly explored — used to split
  /// distances per province along the whole route (not just start/end).
  double evaluateAndAddTrip(
    List<TrackPoint> points, {
    void Function(double midLat, double midLng, double meters, bool isNew)? onSubSegment,
  }) {
    if (points.length < 2) return 0.0;

    double newMeters = 0.0;
    double cumulativeArc = 0.0;
    final Queue<_IndexedSeg> lagQueue = Queue<_IndexedSeg>();

    for (int i = 1; i < points.length; i++) {
      final p1 = points[i - 1];
      final p2 = points[i];

      final stepMeters = LocationService.calculateDistance(
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
      );

      if (stepMeters < 0.5) continue;
      if (stepMeters >= maxValidStepMeters) {
        // Flush lag buffer cleanly across GPS gaps so prior segment stays indexed.
        while (lagQueue.isNotEmpty) {
          _insertSegment(lagQueue.removeFirst());
        }
        // Still report the gap (as already-known distance) every ~1km so the
        // provinces crossed during GPS signal loss are not missed.
        if (onSubSegment != null && stepMeters <= 150000) {
          final gapSteps = (stepMeters / 1000.0).ceil().clamp(1, 150);
          final gapLen = stepMeters / gapSteps;
          for (int g = 0; g < gapSteps; g++) {
            final t = (g + 0.5) / gapSteps;
            onSubSegment(
              p1.latitude + (p2.latitude - p1.latitude) * t,
              p1.longitude + (p2.longitude - p1.longitude) * t,
              gapLen,
              false,
            );
          }
        }
        continue;
      }

      final steps = (stepMeters / maxSubSegMeters).ceil().clamp(1, 500);
      final subLen = stepMeters / steps;

      for (int s = 0; s < steps; s++) {
        final t0 = s / steps;
        final t1 = (s + 1) / steps;
        final aLat = p1.latitude + (p2.latitude - p1.latitude) * t0;
        final aLng = p1.longitude + (p2.longitude - p1.longitude) * t0;
        final bLat = p1.latitude + (p2.latitude - p1.latitude) * t1;
        final bLng = p1.longitude + (p2.longitude - p1.longitude) * t1;

        final midLat = (aLat + bLat) * 0.5;
        final midLng = (aLng + bLng) * 0.5;
        final midArc = cumulativeArc + subLen * 0.5;
        cumulativeArc += subLen;

        // Commit segments that are now safely behind the trailing lag window.
        while (lagQueue.isNotEmpty && (midArc - lagQueue.first.endArc) > lagArcMeters) {
          _insertSegment(lagQueue.removeFirst());
        }

        final isAlreadyExplored = isPointNearExplored(midLat, midLng);
        if (!isAlreadyExplored) {
          newMeters += subLen;
        }
        onSubSegment?.call(midLat, midLng, subLen, !isAlreadyExplored);

        lagQueue.addLast(_IndexedSeg(
          aLat: aLat,
          aLng: aLng,
          bLat: bLat,
          bLng: bLng,
          endArc: cumulativeArc,
        ));
      }
    }

    // Commit remaining segments of this trip before processing subsequent trips.
    while (lagQueue.isNotEmpty) {
      _insertSegment(lagQueue.removeFirst());
    }

    return newMeters;
  }

  /// Evaluates [points] against this index (which should already hold all trips
  /// BEFORE this trip) and produces merged polylines colored as new vs repeated.
  TripSegmentBreakdown classifyTripSegments(List<TrackPoint> points) {
    if (points.length < 2) {
      return const TripSegmentBreakdown(
        newMeters: 0.0,
        repeatedMeters: 0.0,
        newPolylines: [],
        repeatedPolylines: [],
      );
    }

    double newMeters = 0.0;
    double repeatedMeters = 0.0;
    double cumulativeArc = 0.0;
    final Queue<_IndexedSeg> lagQueue = Queue<_IndexedSeg>();

    final List<List<LatLng>> newPolylines = [];
    final List<List<LatLng>> repeatedPolylines = [];
    List<LatLng>? currentSpan;
    bool? currentIsNew;

    void appendSpan(LatLng a, LatLng b, bool isNew) {
      if (currentSpan == null || currentIsNew != isNew) {
        currentSpan = [a, b];
        currentIsNew = isNew;
        if (isNew) {
          newPolylines.add(currentSpan!);
        } else {
          repeatedPolylines.add(currentSpan!);
        }
      } else {
        currentSpan!.add(b);
      }
    }

    for (int i = 1; i < points.length; i++) {
      final p1 = points[i - 1];
      final p2 = points[i];

      final stepMeters = LocationService.calculateDistance(
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
      );

      if (stepMeters < 0.5) continue;
      if (stepMeters >= maxValidStepMeters) {
        currentSpan = null;
        currentIsNew = null;
        while (lagQueue.isNotEmpty) {
          _insertSegment(lagQueue.removeFirst());
        }
        continue;
      }

      final steps = (stepMeters / maxSubSegMeters).ceil().clamp(1, 500);
      final subLen = stepMeters / steps;

      for (int s = 0; s < steps; s++) {
        final t0 = s / steps;
        final t1 = (s + 1) / steps;
        final aLat = p1.latitude + (p2.latitude - p1.latitude) * t0;
        final aLng = p1.longitude + (p2.longitude - p1.longitude) * t0;
        final bLat = p1.latitude + (p2.latitude - p1.latitude) * t1;
        final bLng = p1.longitude + (p2.longitude - p1.longitude) * t1;

        final midLat = (aLat + bLat) * 0.5;
        final midLng = (aLng + bLng) * 0.5;
        final midArc = cumulativeArc + subLen * 0.5;
        cumulativeArc += subLen;

        while (lagQueue.isNotEmpty && (midArc - lagQueue.first.endArc) > lagArcMeters) {
          _insertSegment(lagQueue.removeFirst());
        }

        final isAlreadyExplored = isPointNearExplored(midLat, midLng);
        if (isAlreadyExplored) {
          repeatedMeters += subLen;
        } else {
          newMeters += subLen;
        }

        appendSpan(LatLng(aLat, aLng), LatLng(bLat, bLng), !isAlreadyExplored);

        lagQueue.addLast(_IndexedSeg(
          aLat: aLat,
          aLng: aLng,
          bLat: bLat,
          bLng: bLng,
          endArc: cumulativeArc,
        ));
      }
    }

    while (lagQueue.isNotEmpty) {
      _insertSegment(lagQueue.removeFirst());
    }

    return TripSegmentBreakdown(
      newMeters: newMeters,
      repeatedMeters: repeatedMeters,
      newPolylines: newPolylines,
      repeatedPolylines: repeatedPolylines,
    );
  }
}

/// Incremental tracker used while actively recording a trip in real time.
class LiveExplorationTracker {
  final ExplorationIndex _index;
  final Queue<_IndexedSeg> _lagQueue = Queue<_IndexedSeg>();
  double _cumulativeArc = 0.0;
  double _newMeters = 0.0;
  double? _lastLat;
  double? _lastLng;

  LiveExplorationTracker({double toleranceMeters = ExplorationIndex.defaultToleranceMeters})
      : _index = ExplorationIndex(toleranceMeters: toleranceMeters);

  double get newMeters => _newMeters;

  /// Seeds prior exploration history into the index.
  void seedFromRoutes(Map<String, List<TrackPoint>> priorRoutes, {String? excludeTripId}) {
    for (final entry in priorRoutes.entries) {
      if (entry.key == excludeTripId) continue;
      _index.addTripPoints(entry.value);
    }
  }

  /// Feeds the next recorded GPS point and returns updated unique new meters.
  double addPoint(double lat, double lng) {
    if (_lastLat == null || _lastLng == null) {
      _lastLat = lat;
      _lastLng = lng;
      return _newMeters;
    }

    final p1Lat = _lastLat!;
    final p1Lng = _lastLng!;
    final stepMeters = LocationService.calculateDistance(p1Lat, p1Lng, lat, lng);

    _lastLat = lat;
    _lastLng = lng;

    if (stepMeters < 0.5) return _newMeters;
    if (stepMeters >= ExplorationIndex.maxValidStepMeters) {
      while (_lagQueue.isNotEmpty) {
        _index._insertSegment(_lagQueue.removeFirst());
      }
      return _newMeters;
    }

    final steps = (stepMeters / ExplorationIndex.maxSubSegMeters).ceil().clamp(1, 500);
    final subLen = stepMeters / steps;

    for (int s = 0; s < steps; s++) {
      final t0 = s / steps;
      final t1 = (s + 1) / steps;
      final aLat = p1Lat + (lat - p1Lat) * t0;
      final aLng = p1Lng + (lng - p1Lng) * t0;
      final bLat = p1Lat + (lat - p1Lat) * t1;
      final bLng = p1Lng + (lng - p1Lng) * t1;

      final midLat = (aLat + bLat) * 0.5;
      final midLng = (aLng + bLng) * 0.5;
      final midArc = _cumulativeArc + subLen * 0.5;
      _cumulativeArc += subLen;

      while (_lagQueue.isNotEmpty &&
          (midArc - _lagQueue.first.endArc) > ExplorationIndex.lagArcMeters) {
        _index._insertSegment(_lagQueue.removeFirst());
      }

      if (!_index.isPointNearExplored(midLat, midLng)) {
        _newMeters += subLen;
      }

      _lagQueue.addLast(_IndexedSeg(
        aLat: aLat,
        aLng: aLng,
        bLat: bLat,
        bLng: bLng,
        endArc: _cumulativeArc,
      ));
    }

    return _newMeters;
  }
}

/// High-level exploration analytics helper across a user's trip collection.
class ExplorationCalculator {
  ExplorationCalculator._();

  /// Computes deduplicated exploration metrics chronologically across [trips].
  static ExplorationSummary computeSummary(
    List<Trip> trips,
    Map<String, List<TrackPoint>> routesByTripId, {
    double toleranceMeters = ExplorationIndex.defaultToleranceMeters,
  }) {
    if (trips.isEmpty) {
      return const ExplorationSummary(
        totalUniqueExploredMeters: 0.0,
        totalTraveledMeters: 0.0,
        newMetersByTripId: {},
      );
    }

    // Sort oldest -> newest so earlier trips establish baseline "already explored" roads.
    final chronological = List<Trip>.from(trips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final index = ExplorationIndex(toleranceMeters: toleranceMeters);
    final Map<String, double> newMetersByTripId = {};
    final Map<String, Map<String, double>> traveledByTripProvince = {};
    final Map<String, Map<String, double>> newByTripProvince = {};
    double totalUniqueMeters = 0.0;
    double totalTraveledMeters = 0.0;

    for (final trip in chronological) {
      totalTraveledMeters += trip.totalDistance;

      final pts = (routesByTripId[trip.id]?.isNotEmpty == true)
          ? routesByTripId[trip.id]!
          : trip.points;

      final Map<String, double> traveledProv = {};
      final Map<String, double> newProv = {};

      double tripNewMeters;
      if (pts.length >= 2) {
        final rawNew = index.evaluateAndAddTrip(
          pts,
          onSubSegment: (lat, lng, meters, isNew) {
            final province = VietnamProvinces.matchProvince(lat, lng, null);
            traveledProv[province] = (traveledProv[province] ?? 0.0) + meters;
            if (isNew) {
              newProv[province] = (newProv[province] ?? 0.0) + meters;
            }
          },
        );
        // Never report newMeters > recorded totalDistance due to sub-step approximation.
        tripNewMeters = trip.totalDistance > 0
            ? rawNew.clamp(0.0, trip.totalDistance)
            : rawNew;

        // Keep per-province new meters consistent with the clamped trip total.
        if (rawNew > 0 && tripNewMeters < rawNew) {
          final scale = tripNewMeters / rawNew;
          newProv.updateAll((_, v) => v * scale);
        }

        // Always count the start & end provinces even for very short trips.
        final startProv = VietnamProvinces.matchProvince(
            pts.first.latitude, pts.first.longitude, trip.startAddress);
        final endProv = VietnamProvinces.matchProvince(
            pts.last.latitude, pts.last.longitude, trip.endAddress);
        traveledProv.putIfAbsent(startProv, () => 0.0);
        traveledProv.putIfAbsent(endProv, () => 0.0);
      } else {
        // Fallback for synthetic/imported summary trips without coordinate geometry.
        tripNewMeters = trip.totalDistance;
        final lat = pts.isNotEmpty ? pts.first.latitude : 0.0;
        final lng = pts.isNotEmpty ? pts.first.longitude : 0.0;
        final province = VietnamProvinces.matchProvince(
          lat,
          lng,
          '${trip.startAddress ?? ''} ${trip.title}',
        );
        traveledProv[province] = trip.totalDistance;
        newProv[province] = trip.totalDistance;
      }

      newMetersByTripId[trip.id] = tripNewMeters;
      traveledByTripProvince[trip.id] = traveledProv;
      newByTripProvince[trip.id] = newProv;
      totalUniqueMeters += tripNewMeters;
    }

    return ExplorationSummary(
      totalUniqueExploredMeters: totalUniqueMeters,
      totalTraveledMeters: totalTraveledMeters,
      newMetersByTripId: newMetersByTripId,
      traveledMetersByTripProvince: traveledByTripProvince,
      newMetersByTripProvince: newByTripProvince,
    );
  }
}
