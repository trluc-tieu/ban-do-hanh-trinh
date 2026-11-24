import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Streams device compass heading (degrees clockwise from north, 0..360)
/// from the native Android Rotation Vector sensor via EventChannel.
///
/// Exposed as a [ValueNotifier] so that only the user location marker
/// rebuilds when the phone rotates (not the whole screen).
class CompassService {
  static final CompassService _instance = CompassService._internal();
  factory CompassService() => _instance;
  CompassService._internal();

  static const EventChannel _channel = EventChannel('trluc.top/compass');

  /// Current device heading in degrees (null when sensor unavailable).
  final ValueNotifier<double?> heading = ValueNotifier<double?>(null);

  StreamSubscription<dynamic>? _sub;
  AppLifecycleListener? _lifecycle;
  bool _wanted = false;
  bool _unsupported = false;

  bool get isAvailable => !_unsupported;

  /// Begin listening to compass updates (auto pauses while app is in background).
  void start() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _wanted = true;
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        if (_wanted) _subscribe();
      },
      onPause: _unsubscribe,
    );
    _subscribe();
  }

  void stop() {
    _wanted = false;
    _unsubscribe();
  }

  void _subscribe() {
    if (_sub != null || _unsupported) return;
    try {
      _sub = _channel.receiveBroadcastStream().listen(
        (dynamic value) {
          if (value is num) {
            heading.value = smoothHeading(heading.value, value.toDouble());
          }
        },
        onError: (Object _) {
          _unsupported = true;
          _unsubscribe();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _unsupported = true;
    }
  }

  void _unsubscribe() {
    _sub?.cancel();
    _sub = null;
  }

  /// Low-pass filter that handles the 359° -> 0° wrap-around correctly.
  static double smoothHeading(double? previous, double next, {double factor = 0.35}) {
    final n = normalize(next);
    if (previous == null) return n;
    var delta = n - previous;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return normalize(previous + delta * factor);
  }

  static double normalize(double deg) {
    final v = deg % 360;
    return v < 0 ? v + 360 : v;
  }
}
