import 'package:flutter/material.dart';

/// Supported categories for user-pinned map locations (with distinct icons & colors).
enum PinnedPlaceCategory {
  work,
  school,
  cafe,
  restaurant,
  scenic,
  parking,
  favorite,
}

extension PinnedPlaceCategoryInfo on PinnedPlaceCategory {
  String get key => name;

  String get label {
    switch (this) {
      case PinnedPlaceCategory.work:
        return 'Công ty / Cơ quan';
      case PinnedPlaceCategory.school:
        return 'Trường học';
      case PinnedPlaceCategory.cafe:
        return 'Quán quen / Café';
      case PinnedPlaceCategory.restaurant:
        return 'Quán ăn / Nhà hàng';
      case PinnedPlaceCategory.scenic:
        return 'Điểm tham quan';
      case PinnedPlaceCategory.parking:
        return 'Bãi gửi xe';
      case PinnedPlaceCategory.favorite:
        return 'Yêu thích';
    }
  }

  String get defaultName {
    switch (this) {
      case PinnedPlaceCategory.work:
        return 'Công ty';
      case PinnedPlaceCategory.school:
        return 'Trường học';
      case PinnedPlaceCategory.cafe:
        return 'Quán quen';
      case PinnedPlaceCategory.restaurant:
        return 'Quán ăn';
      case PinnedPlaceCategory.scenic:
        return 'Điểm tham quan';
      case PinnedPlaceCategory.parking:
        return 'Bãi xe';
      case PinnedPlaceCategory.favorite:
        return 'Điểm yêu thích';
    }
  }

  IconData get icon {
    switch (this) {
      case PinnedPlaceCategory.work:
        return Icons.business_center_rounded;
      case PinnedPlaceCategory.school:
        return Icons.school_rounded;
      case PinnedPlaceCategory.cafe:
        return Icons.local_cafe_rounded;
      case PinnedPlaceCategory.restaurant:
        return Icons.restaurant_rounded;
      case PinnedPlaceCategory.scenic:
        return Icons.landscape_rounded;
      case PinnedPlaceCategory.parking:
        return Icons.local_parking_rounded;
      case PinnedPlaceCategory.favorite:
        return Icons.favorite_rounded;
    }
  }

  Color get color {
    switch (this) {
      case PinnedPlaceCategory.work:
        return const Color(0xFF2563EB);
      case PinnedPlaceCategory.school:
        return const Color(0xFF6366F1);
      case PinnedPlaceCategory.cafe:
        return const Color(0xFF92400E);
      case PinnedPlaceCategory.restaurant:
        return const Color(0xFFEA580C);
      case PinnedPlaceCategory.scenic:
        return const Color(0xFF059669);
      case PinnedPlaceCategory.parking:
        return const Color(0xFF0891B2);
      case PinnedPlaceCategory.favorite:
        return const Color(0xFFE11D48);
    }
  }

  static PinnedPlaceCategory fromKey(String? raw) {
    if (raw == null) return PinnedPlaceCategory.favorite;
    for (final c in PinnedPlaceCategory.values) {
      if (c.name == raw) return c;
    }
    return PinnedPlaceCategory.favorite;
  }
}

/// A custom place pinned by the user on the map (work, cafe, school, etc.).
class PinnedPlace {
  final String id;
  final String name;
  final PinnedPlaceCategory category;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final String? note;
  final DateTime createdAt;

  const PinnedPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 50,
    this.note,
    required this.createdAt,
  });

  PinnedPlace copyWith({
    String? name,
    PinnedPlaceCategory? category,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    String? note,
  }) {
    return PinnedPlace(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.key,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PinnedPlace.fromMap(Map<String, dynamic> map) {
    return PinnedPlace(
      id: map['id'] as String,
      name: map['name'] as String,
      category: PinnedPlaceCategoryInfo.fromKey(map['category'] as String?),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: (map['radius_meters'] as num?)?.toInt() ?? 50,
      note: map['note'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
