class StayPoint {
  final String id;
  final String tripId;
  final double latitude;
  final double longitude;
  final DateTime arrivalTime;
  DateTime departureTime;
  String? address;
  String status; // 'pending', 'confirmed', 'rejected'
  String? confirmedName;
  String? note;

  StayPoint({
    required this.id,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.arrivalTime,
    required this.departureTime,
    this.address,
    this.status = 'pending',
    this.confirmedName,
    this.note,
  });

  int get durationMinutes {
    return departureTime.difference(arrivalTime).inMinutes;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'arrival_time': arrivalTime.toIso8601String(),
      'departure_time': departureTime.toIso8601String(),
      'address': address,
      'status': status,
      'confirmed_name': confirmedName,
      'note': note,
    };
  }

  factory StayPoint.fromMap(Map<String, dynamic> map) {
    return StayPoint(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      arrivalTime: DateTime.parse(map['arrival_time'] as String),
      departureTime: DateTime.parse(map['departure_time'] as String),
      address: map['address'] as String?,
      status: map['status'] as String? ?? 'pending',
      confirmedName: map['confirmed_name'] as String?,
      note: map['note'] as String?,
    );
  }
}
