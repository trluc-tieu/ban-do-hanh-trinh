import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/pinned_place.dart';
import '../models/vehicle_type.dart';
import '../services/compass_service.dart';
import '../theme/app_theme.dart';

/// Live user marker:
/// - Idle: blue dot with a soft direction beam showing where the phone points.
/// - Recording: circular vehicle badge (customizable icon & color) with a
///   direction pointer following the phone compass heading.
///
/// Must be placed in a [Marker] with `rotate: true` (kept upright on screen);
/// the pointer compensates for the current map rotation itself.
class UserLocationMarker extends StatelessWidget {
  final bool vehicleMode;
  final VehicleType vehicleType;
  final Color vehicleColor;

  /// Fallback heading (GPS course) when compass sensor is unavailable.
  final double? fallbackHeading;

  const UserLocationMarker({
    super.key,
    required this.vehicleMode,
    required this.vehicleType,
    required this.vehicleColor,
    this.fallbackHeading,
  });

  static const double size = 72;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: CompassService().heading,
      builder: (ctx, compassHeading, _) {
        final heading = compassHeading ?? fallbackHeading;
        double mapRotation = 0;
        try {
          mapRotation = MapCamera.of(ctx).rotation;
        } catch (_) {}

        // Angle on screen = geographic heading + map rotation (clockwise degrees)
        final screenAngleDeg = heading == null ? null : CompassService.normalize(heading + mapRotation);
        final screenAngleRad = screenAngleDeg == null ? 0.0 : screenAngleDeg * math.pi / 180.0;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (screenAngleDeg != null)
                Transform.rotate(
                  angle: screenAngleRad,
                  child: CustomPaint(
                    size: const Size(size, size),
                    painter: _HeadingBeamPainter(
                      color: vehicleMode ? vehicleColor : AppTheme.primary,
                      vehicleMode: vehicleMode,
                    ),
                  ),
                ),
              if (vehicleMode)
                _buildVehicleBadge(screenAngleDeg, screenAngleRad)
              else
                _buildIdleDot(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIdleDot() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
      ),
    );
  }

  Widget _buildVehicleBadge(double? screenAngleDeg, double screenAngleRad) {
    Widget icon = Icon(vehicleType.icon, color: Colors.white, size: 22);

    if (vehicleType.rotatesWithHeading) {
      icon = Transform.rotate(angle: screenAngleRad, child: icon);
    } else if (vehicleType.isSideView && screenAngleDeg != null && screenAngleDeg > 180) {
      // Mirror side-view vehicles when heading towards the left half of the screen
      icon = Transform.flip(flipX: true, child: icon);
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: vehicleColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: vehicleColor.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 1),
          const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}

/// Paints a direction indicator pointing "up" (rotated by the parent):
/// a translucent beam cone plus a solid pointer tip.
class _HeadingBeamPainter extends CustomPainter {
  final Color color;
  final bool vehicleMode;

  _HeadingBeamPainter({required this.color, required this.vehicleMode});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Beam cone (±30°)
    final beamPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    final beam = Path()..moveTo(c.dx, c.dy);
    const half = 30 * math.pi / 180;
    beam.arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2 - half, half * 2, false);
    beam.close();
    canvas.drawPath(beam, beamPaint);

    // Pointer tip just outside the central badge
    final tipDistance = vehicleMode ? 25.0 : 15.0;
    final tip = Path()
      ..moveTo(c.dx, c.dy - tipDistance - 9)
      ..lineTo(c.dx - 7, c.dy - tipDistance + 1)
      ..lineTo(c.dx + 7, c.dy - tipDistance + 1)
      ..close();
    canvas.drawPath(
      tip,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(tip, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeadingBeamPainter old) =>
      old.color != color || old.vehicleMode != vehicleMode;
}

/// House pin marking the user's "Nhà" location.
class HomePinMarker extends StatelessWidget {
  const HomePinMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: const Text(
            'Nhà',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2))],
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 18),
        ),
      ],
    );
  }
}

/// Custom icon pin marking a user-defined [PinnedPlace] (work, school, cafe, scenic spot...).
class PinnedPlaceMarker extends StatelessWidget {
  final PinnedPlace place;

  const PinnedPlaceMarker({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final color = place.category.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
          child: Text(
            place.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2))],
          ),
          child: Icon(place.category.icon, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}
