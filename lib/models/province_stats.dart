class ProvinceStats {
  final String provinceName;
  final double distanceKm;
  final int tripCount;
  final int waypointCount;
  final int rank;

  ProvinceStats({
    required this.provinceName,
    required this.distanceKm,
    required this.tripCount,
    required this.waypointCount,
    this.rank = 0,
  });

  String get tierName {
    if (distanceKm > 100) return 'Khám Phá Toàn Diện';
    if (distanceKm > 40) return 'Khám Phá Sâu';
    if (distanceKm > 10) return 'Đã Ghé Thăm';
    return 'Mới Đặt Chân';
  }
}

class VietnamProvinces {
  static const List<String> allProvinces = [
    'Hà Nội',
    'TP. Hồ Chí Minh',
    'Đà Nẵng',
    'Hải Phòng',
    'Cần Thơ',
    'An Giang',
    'Bà Rịa - Vũng Tàu',
    'Bắc Giang',
    'Bắc Kạn',
    'Bạc Liêu',
    'Bắc Ninh',
    'Bến Tre',
    'Bình Định',
    'Bình Dương',
    'Bình Phước',
    'Bình Thuận',
    'Cà Mau',
    'Cao Bằng',
    'Đắk Lắk',
    'Đắk Nông',
    'Điện Biên',
    'Đồng Nai',
    'Đồng Tháp',
    'Gia Lai',
    'Hà Giang',
    'Hà Nam',
    'Hà Tĩnh',
    'Hải Dương',
    'Hậu Giang',
    'Hoà Bình',
    'Hưng Yên',
    'Khánh Hoà',
    'Kiên Giang',
    'Kon Tum',
    'Lai Châu',
    'Lâm Đồng',
    'Lạng Sơn',
    'Lào Cai',
    'Long An',
    'Nam Định',
    'Nghệ An',
    'Ninh Bình',
    'Ninh Thuận',
    'Phú Thọ',
    'Phú Yên',
    'Quảng Bình',
    'Quảng Nam',
    'Quảng Ngãi',
    'Quảng Ninh',
    'Quảng Trị',
    'Sóc Trăng',
    'Sơn La',
    'Tây Ninh',
    'Thái Bình',
    'Thái Nguyên',
    'Thanh Hoá',
    'Thừa Thiên Huế',
    'Tiền Giang',
    'Trà Vinh',
    'Tuyên Quang',
    'Vĩnh Long',
    'Vĩnh Phúc',
    'Yên Bái',
  ];

  /// Approximate matching of coordinates or address string to province
  static String matchProvince(double lat, double lng, String? address) {
    if (address != null && address.isNotEmpty) {
      final lower = address.toLowerCase();
      for (final p in allProvinces) {
        if (lower.contains(p.toLowerCase())) {
          return p;
        }
      }
      if (lower.contains('hồ chí minh') || lower.contains('sài gòn') || lower.contains('tphcm')) {
        return 'TP. Hồ Chí Minh';
      }
      if (lower.contains('hà nội') || lower.contains('ha noi')) return 'Hà Nội';
      if (lower.contains('đà nẵng') || lower.contains('da nang')) return 'Đà Nẵng';
    }

    // Geographic bounding approximation in Vietnam
    if (lat >= 20.8 && lat <= 21.3 && lng >= 105.5 && lng <= 106.1) {
      return 'Hà Nội';
    } else if (lat >= 10.6 && lat <= 11.0 && lng >= 106.5 && lng <= 107.0) {
      return 'TP. Hồ Chí Minh';
    } else if (lat >= 15.9 && lat <= 16.2 && lng >= 108.1 && lng <= 108.4) {
      return 'Đà Nẵng';
    } else if (lat >= 20.7 && lat <= 21.0 && lng >= 106.5 && lng <= 107.0) {
      return 'Hải Phòng';
    } else if (lat >= 20.8 && lat <= 21.6 && lng >= 106.8 && lng <= 108.0) {
      return 'Quảng Ninh';
    } else if (lat >= 11.8 && lat <= 12.2 && lng >= 108.3 && lng <= 108.6) {
      return 'Lâm Đồng';
    } else if (lat >= 12.1 && lat <= 12.5 && lng >= 109.1 && lng <= 109.3) {
      return 'Khánh Hoà';
    } else if (lat >= 20.1 && lat <= 20.4 && lng >= 105.8 && lng <= 106.1) {
      return 'Ninh Bình';
    } else if (lat >= 22.3 && lat <= 22.5 && lng >= 103.7 && lng <= 104.0) {
      return 'Lào Cai';
    }

    // Default northern/central/southern fallback
    if (lat > 19.5) return 'Hà Nội';
    if (lat > 14.0) return 'Đà Nẵng';
    return 'TP. Hồ Chí Minh';
  }
}
