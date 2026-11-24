import 'package:flutter/material.dart';

/// Vehicle icon styles shown on the map while a journey is being recorded.
enum VehicleType {
  motorbike,
  car,
  bicycle,
  walking,
  electricScooter,
  bus,
  arrow,
}

extension VehicleTypeInfo on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.motorbike:
        return 'Xe máy';
      case VehicleType.car:
        return 'Ô tô';
      case VehicleType.bicycle:
        return 'Xe đạp';
      case VehicleType.walking:
        return 'Đi bộ';
      case VehicleType.electricScooter:
        return 'Xe điện';
      case VehicleType.bus:
        return 'Xe buýt / Xe khách';
      case VehicleType.arrow:
        return 'Mũi tên điều hướng';
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleType.motorbike:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car_filled;
      case VehicleType.bicycle:
        return Icons.pedal_bike;
      case VehicleType.walking:
        return Icons.directions_walk;
      case VehicleType.electricScooter:
        return Icons.electric_moped;
      case VehicleType.bus:
        return Icons.directions_bus_filled;
      case VehicleType.arrow:
        return Icons.navigation_rounded;
    }
  }

  /// Side-view icons (drawn facing right) are mirrored when heading points left
  /// so the vehicle never appears to drive backwards.
  bool get isSideView {
    switch (this) {
      case VehicleType.motorbike:
      case VehicleType.bicycle:
      case VehicleType.walking:
      case VehicleType.electricScooter:
        return true;
      default:
        return false;
    }
  }

  /// The arrow icon itself encodes direction, so it is rotated directly.
  bool get rotatesWithHeading => this == VehicleType.arrow;

  static VehicleType fromIndex(int? index) {
    if (index == null || index < 0 || index >= VehicleType.values.length) {
      return VehicleType.motorbike;
    }
    return VehicleType.values[index];
  }
}

/// Palette for customizing the vehicle marker color.
const List<Color> kVehicleColors = [
  Color(0xFF0D9488), // teal (app primary)
  Color(0xFF2563EB), // blue
  Color(0xFFDC2626), // red
  Color(0xFFF59E0B), // amber
  Color(0xFF7C3AED), // violet
  Color(0xFFDB2777), // pink
  Color(0xFF16A34A), // green
  Color(0xFF0F172A), // slate
];
