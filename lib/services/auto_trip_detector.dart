import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

/// Lightweight location sample fed into [AutoTripDetector].
class AutoTripSample {
  final double latitude;
  final double longitude;
  final double speedMps; // negative if unknown
  final double accuracyMeters; // 0 if unknown
  final double altitude;
  final DateTime timestamp;

  const AutoTripSample({
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.accuracyMeters,
    this.altitude = 0.0,
    required this.timestamp,
  });

  factory AutoTripSample.fromPosition(Position pos) {
    return AutoTripSample(
      latitude: pos.latitude,
      longitude: pos.longitude,
      speedMps: pos.speed,
      accuracyMeters: pos.accuracy,
      altitude: pos.altitude,
      timestamp: pos.timestamp,
    );
  }
}

class _BufferedSample {
  final AutoTripSample sample;
  final double effectiveSpeedKmh;

  const _BufferedSample({
    required this.sample,
    required this.effectiveSpeedKmh,
  });
}

/// Outcome returned by [AutoTripDetector.evaluate].
class AutoTripTriggerResult {
  final bool triggered;
  final List<AutoTripSample> departureSamples;
  final double netDisplacementMeters;
  final double avgSpeedKmh;

  const AutoTripTriggerResult({
    required this.triggered,
    this.departureSamples = const [],
    this.netDisplacementMeters = 0.0,
    this.avgSpeedKmh = 0.0,
  });

  static const none = AutoTripTriggerResult(triggered: false);
}

/// Validates sustained high-speed, large-range travel before auto-starting a trip
/// in background monitoring mode.
///
/// Rejects:
/// - Poor indoor GPS fixes ([accuracyMeters] > [maxAccuracyMeters])
/// - Single isolated GPS jump/teleport spikes
/// - Stationary GPS jitter/oscillation around a fixed point
/// - Slow walking or wandering around a single building/park
class AutoTripDetector {
  double minSpeedKmh;
  int minRangeMeters;
  final double maxAccuracyMeters;
  final int minDurationSeconds;
  final int minFastSamples;
  final double minStraightLineRatio;

  AutoTripSample? _anchor;
  final List<_BufferedSample> _buffer = [];

  AutoTripDetector({
    this.minSpeedKmh = 12.0,
    this.minRangeMeters = 150,
    this.maxAccuracyMeters = 45.0,
    this.minDurationSeconds = 8,
    this.minFastSamples = 3,
    this.minStraightLineRatio = 0.45,
  });

  void updateThresholds({
    double? minSpeedKmh,
    int? minRangeMeters,
  }) {
    if (minSpeedKmh != null) this.minSpeedKmh = minSpeedKmh;
    if (minRangeMeters != null) this.minRangeMeters = minRangeMeters;
  }

  void reset() {
    _anchor = null;
    _buffer.clear();
  }

  AutoTripTriggerResult evaluate(AutoTripSample sample) {
    // 1. Ignore noisy low-accuracy fixes so indoor drift cannot pollute anchor/motion checks.
    if (sample.accuracyMeters > maxAccuracyMeters) {
      return AutoTripTriggerResult.none;
    }

    // 2. Prune stale samples (> 90s old).
    _buffer.removeWhere(
      (b) => sample.timestamp.difference(b.sample.timestamp).inSeconds > 90,
    );

    // 3. Compute effective speed & reject impossible GPS teleport spikes.
    double effSpeedKmh = sample.speedMps >= 0 ? sample.speedMps * 3.6 : 0.0;
    if (_buffer.isNotEmpty) {
      final prev = _buffer.last.sample;
      final dt = sample.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
      if (dt > 0.2) {
        final stepMeters = LocationService.calculateDistance(
          prev.latitude,
          prev.longitude,
          sample.latitude,
          sample.longitude,
        );
        final segSpeedKmh = (stepMeters / dt) * 3.6;
        if (segSpeedKmh > 220.0 || (stepMeters > 500.0 && dt < 5.0)) {
          // Teleport spike -> discard without touching anchor.
          return AutoTripTriggerResult.none;
        }
        if (sample.speedMps < 0 && dt >= 2.0 && sample.accuracyMeters <= 25.0) {
          effSpeedKmh = segSpeedKmh;
        }
      }
    }

    _buffer.add(_BufferedSample(sample: sample, effectiveSpeedKmh: effSpeedKmh));

    // 4. Maintain stationary anchor so walking slowly or sitting still re-centers cleanly.
    if (_anchor == null) {
      _anchor = sample;
      return AutoTripTriggerResult.none;
    }

    final anchorDist = LocationService.calculateDistance(
      _anchor!.latitude,
      _anchor!.longitude,
      sample.latitude,
      sample.longitude,
    );

    final hasRecentFastMotion = _buffer.any(
      (b) =>
          sample.timestamp.difference(b.sample.timestamp).inSeconds <= 25 &&
          b.effectiveSpeedKmh >= minSpeedKmh * 0.75,
    );

    // If user hasn't shown sustained fast motion recently and stays within a tight area,
    // re-anchor so slow wandering inside a mall/campus doesn't accumulate net range over time.
    if (!hasRecentFastMotion && anchorDist < minRangeMeters * 0.65) {
      if (sample.timestamp.difference(_anchor!.timestamp).inSeconds >= 25) {
        _anchor = sample;
      }
      return AutoTripTriggerResult.none;
    }

    // 5. Check Large Range criterion.
    if (anchorDist < minRangeMeters) {
      return AutoTripTriggerResult.none;
    }

    // 6. Identify the active departure leg from the last low-speed sample near anchor.
    int startIdx = 0;
    for (int i = _buffer.length - 1; i >= 0; i--) {
      if (_buffer[i].effectiveSpeedKmh < minSpeedKmh * 0.5) {
        startIdx = i;
        break;
      }
    }

    final leg = _buffer.sublist(startIdx);
    if (leg.length < minFastSamples) {
      return AutoTripTriggerResult.none;
    }

    final legDurationSec =
        sample.timestamp.difference(leg.first.sample.timestamp).inSeconds;
    if (legDurationSec < minDurationSeconds) {
      return AutoTripTriggerResult.none;
    }

    // Require sustained fast samples & still moving right now.
    final fastSamples =
        leg.where((b) => b.effectiveSpeedKmh >= minSpeedKmh * 0.85).length;
    if (fastSamples < minFastSamples || effSpeedKmh < minSpeedKmh * 0.8) {
      return AutoTripTriggerResult.none;
    }

    // Compute leg path length and check anti-oscillation ratio.
    double legPathMeters = 0.0;
    for (int i = 1; i < leg.length; i++) {
      legPathMeters += LocationService.calculateDistance(
        leg[i - 1].sample.latitude,
        leg[i - 1].sample.longitude,
        leg[i].sample.latitude,
        leg[i].sample.longitude,
      );
    }

    final legNetMeters = LocationService.calculateDistance(
      leg.first.sample.latitude,
      leg.first.sample.longitude,
      sample.latitude,
      sample.longitude,
    );

    final effectiveRange = math.max(anchorDist, legNetMeters);
    if (effectiveRange < minRangeMeters) {
      return AutoTripTriggerResult.none;
    }

    final straightLineRatio = legNetMeters / math.max(1.0, legPathMeters);
    if (straightLineRatio < minStraightLineRatio) {
      return AutoTripTriggerResult.none;
    }

    final avgLegSpeedKmh = (legPathMeters / legDurationSec) * 3.6;
    if (avgLegSpeedKmh < minSpeedKmh * 0.8) {
      return AutoTripTriggerResult.none;
    }

    // Prepend _anchor if it predates leg.first and was close to departure spot.
    final departureSamples = <AutoTripSample>[];
    if (_anchor!.timestamp.isBefore(leg.first.sample.timestamp) &&
        LocationService.calculateDistance(
              _anchor!.latitude,
              _anchor!.longitude,
              leg.first.sample.latitude,
              leg.first.sample.longitude,
            ) <=
            60.0) {
      departureSamples.add(_anchor!);
    }
    departureSamples.addAll(leg.map((b) => b.sample));

    reset();
    return AutoTripTriggerResult(
      triggered: true,
      departureSamples: departureSamples,
      netDisplacementMeters: effectiveRange,
      avgSpeedKmh: avgLegSpeedKmh,
    );
  }
}
