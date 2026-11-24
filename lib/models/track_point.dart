import 'vehicle_type.dart';

class TrackPoint {
  final int? id;
  final String tripId;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed; // in m/s
  final double accuracy;
  final DateTime timestamp;
  final VehicleType vehicleType;

  TrackPoint({
    this.id,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.accuracy = 0.0,
    required this.timestamp,
    this.vehicleType = VehicleType.motorbike,
  });

  /// Speed converted to kilometers per hour
  double get speedKmh => speed > 0 ? (speed * 3.6) : 0.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
      'vehicle_type': vehicleType.index,
    };
  }

  factory TrackPoint.fromMap(Map<String, dynamic> map) {
    return TrackPoint(
      id: map['id'] as int?,
      tripId: map['trip_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(map['timestamp'] as String),
      vehicleType: VehicleTypeInfo.fromIndex((map['vehicle_type'] as num?)?.toInt()),
    );
  }
}
