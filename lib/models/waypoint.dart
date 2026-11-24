class Waypoint {
  final String id;
  final String tripId;
  final String name;
  final String? note;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? photoPath;

  Waypoint({
    required this.id,
    required this.tripId,
    required this.name,
    this.note,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.photoPath,
  });

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'name': name,
      'note': note,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'photo_path': photoPath,
    };
  }

  factory Waypoint.fromMap(Map<String, dynamic> map) {
    return Waypoint(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      name: map['name'] as String,
      note: map['note'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      photoPath: map['photo_path'] as String?,
    );
  }
}
