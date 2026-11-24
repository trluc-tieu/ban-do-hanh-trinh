import 'track_point.dart';
import 'vehicle_type.dart';
import 'waypoint.dart';

class Trip {
  final String id;
  String title;
  final DateTime startTime;
  DateTime? endTime;
  double totalDistance; // in meters
  double newDistance; // newly explored unique distance in meters
  int durationSeconds;
  double maxSpeed; // in m/s
  double avgSpeed; // in m/s
  int pointCount;
  String? startAddress;
  String? endAddress;
  bool isCompleted;
  VehicleType vehicleType;
  List<VehicleType> vehicleTypesUsed;
  List<TrackPoint> points;
  List<Waypoint> waypoints;

  Trip({
    required this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    this.totalDistance = 0.0,
    this.newDistance = 0.0,
    this.durationSeconds = 0,
    this.maxSpeed = 0.0,
    this.avgSpeed = 0.0,
    this.pointCount = 0,
    this.startAddress,
    this.endAddress,
    this.isCompleted = false,
    this.vehicleType = VehicleType.motorbike,
    List<VehicleType>? vehicleTypesUsed,
    List<TrackPoint>? points,
    List<Waypoint>? waypoints,
  })  : vehicleTypesUsed = vehicleTypesUsed != null && vehicleTypesUsed.isNotEmpty
            ? List<VehicleType>.from(vehicleTypesUsed)
            : [vehicleType],
        points = points ?? [],
        waypoints = waypoints ?? [];

  /// Records a vehicle switch during an active journey if different from the latest segment's vehicle.
  void recordVehicleSwitch(VehicleType next) {
    if (vehicleTypesUsed.isEmpty || vehicleTypesUsed.last != next) {
      vehicleTypesUsed.add(next);
    }
  }

  /// Readable vehicle timeline summary (e.g., "Xe máy" or "Xe máy → Ô tô").
  String get vehicleSummaryLabel {
    if (vehicleTypesUsed.isEmpty) return vehicleType.label;
    return vehicleTypesUsed.map((v) => v.label).join(' → ');
  }

  /// Total distance traveled in this trip (km)
  double get distanceKm => totalDistance / 1000.0;

  /// Newly explored unique road distance contributed by this trip (km)
  double get newDistanceKm => newDistance / 1000.0;

  /// Repeated (previously explored) distance in this trip (meters)
  double get repeatedDistance => (totalDistance - newDistance).clamp(0.0, totalDistance);

  /// Repeated (previously explored) distance in this trip (km)
  double get repeatedDistanceKm => repeatedDistance / 1000.0;

  /// Percentage (0..100) of this trip that was newly explored
  double get newDiscoveryPercent =>
      totalDistance > 0 ? ((newDistance / totalDistance) * 100.0).clamp(0.0, 100.0) : 0.0;

  /// Max speed in km/h
  double get maxSpeedKmh => maxSpeed * 3.6;

  /// Average speed in km/h
  double get avgSpeedKmh => avgSpeed * 3.6;

  /// Formatted duration string hh:mm:ss
  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'total_distance': totalDistance,
      'new_distance': newDistance,
      'duration_seconds': durationSeconds,
      'max_speed': maxSpeed,
      'avg_speed': avgSpeed,
      'point_count': pointCount,
      'start_address': startAddress,
      'end_address': endAddress,
      'is_completed': isCompleted ? 1 : 0,
      'vehicle_type': vehicleType.index,
      'vehicle_types': vehicleTypesUsed.map((v) => v.index).join(','),
    };
  }

  factory Trip.fromMap(Map<String, dynamic> map, {List<TrackPoint>? points, List<Waypoint>? waypoints}) {
    final primaryVehicle = VehicleTypeInfo.fromIndex((map['vehicle_type'] as num?)?.toInt());
    final rawList = map['vehicle_types'] as String?;
    List<VehicleType>? parsedSequence;
    if (rawList != null && rawList.trim().isNotEmpty) {
      parsedSequence = rawList
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .map(VehicleTypeInfo.fromIndex)
          .toList();
    }

    return Trip(
      id: map['id'] as String,
      title: map['title'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time'] as String) : null,
      totalDistance: (map['total_distance'] as num?)?.toDouble() ?? 0.0,
      newDistance: (map['new_distance'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      maxSpeed: (map['max_speed'] as num?)?.toDouble() ?? 0.0,
      avgSpeed: (map['avg_speed'] as num?)?.toDouble() ?? 0.0,
      pointCount: (map['point_count'] as num?)?.toInt() ?? 0,
      startAddress: map['start_address'] as String?,
      endAddress: map['end_address'] as String?,
      isCompleted: (map['is_completed'] as int?) == 1,
      vehicleType: primaryVehicle,
      vehicleTypesUsed: parsedSequence,
      points: points,
      waypoints: waypoints,
    );
  }
}
