import 'dart:math';
import '../models/monthly_stats.dart';
import '../models/province_stats.dart';
import '../models/trip.dart';
import '../providers/tracking_provider.dart';

/// Generates friendly, conversational Vietnamese travel-buddy notes
/// grounded in real exploration metrics (excluding formal screens like Settings).
class CompanionQuotes {
  CompanionQuotes._();

  static const String launchGreeting =
      'Chúng ta bắt đầu khám phá những cung đường mới chứ?';

  static final List<String> _idlePool = [
    launchGreeting,
    'Hôm nay tụi mình thử rẽ sang một con đường mới xem có gì hay nhé?',
    'Xách ba lô hay nổ máy lên nào, bản đồ vẫn đang đợi dấu chân tụi mình đó!',
    'Cứ đi thôi, mọi ngõ ngách mới lạ hôm nay đều sẽ sáng lên trên bản đồ!',
  ];

  static String pickDiscoverIdleQuote({int? seed}) {
    if (seed == null) return launchGreeting;
    return _idlePool[seed.abs() % _idlePool.length];
  }

  /// Counts how many trips in [trips] started or ended at "Nhà".
  static int countHomeTrips(List<Trip> trips) {
    int count = 0;
    for (final t in trips) {
      if (t.startAddress == TrackingProvider.homeAddressLabel ||
          t.endAddress == TrackingProvider.homeAddressLabel) {
        count++;
      }
    }
    return count;
  }

  /// Friendly header commentary for the 63-Province Ranking screen.
  static String pickProvinceSummaryQuote({
    required int exploredCount,
    required List<ProvinceStats> ranked,
    required List<Trip> trips,
    Random? random,
  }) {
    if (exploredCount == 0 || ranked.isEmpty) {
      return 'Bản đồ Việt Nam còn mới tinh nè — tụi mình cùng nhau mở khoá tỉnh đầu tiên nhé!';
    }

    final top = ranked.first;
    final homeTrips = countHomeTrips(trips);
    final candidates = <String>[];

    if (top.tripCount >= 3 || top.distanceKm >= 25) {
      candidates.add(
        'Bạn đã đến ${top.provinceName} rất nhiều lần, có lẽ đây chính là quê hương của bạn!',
      );
      candidates.add(
        'Có lẽ ${top.provinceName} là nơi bắt đầu của các chuyến hành trình tụi mình!',
      );
    } else {
      candidates.add(
        'Vừa mở khoá ${top.provinceName} (${top.distanceKm.toStringAsFixed(1)} km) — bước khởi đầu tuyệt vời luôn!',
      );
    }

    if (homeTrips >= 2) {
      candidates.add(
        'Có $homeTrips chuyến đi bắt đầu hoặc trở về Nhà — mọi nẻo đường đều nối về điểm tựa quen thuộc.',
      );
    }

    if (exploredCount >= 10) {
      candidates.add(
        'Tụi mình đã đặt chân tới $exploredCount/63 tỉnh thành rồi đó! Còn ${63 - exploredCount} vùng đất nữa đang đợi phía trước.',
      );
    } else if (exploredCount >= 2) {
      candidates.add(
        'Đã ghi dấu $exploredCount tỉnh rồi nè, cuối tuần tới tụi mình thử nối dài thêm 1 tỉnh mới nha!',
      );
    }

    final rng = random ?? Random(DateTime.now().minute + exploredCount);
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Short micro-comment shown inside top / frequent province cards.
  static String? pickProvinceCardNote(ProvinceStats stats) {
    if (stats.distanceKm <= 0 && stats.tripCount <= 0) return null;
    if (stats.rank == 1 && stats.tripCount >= 4) {
      return 'Bạn đã đến đây rất nhiều lần, có lẽ đây chính là quê hương của bạn!';
    }
    if (stats.rank == 1 && stats.tripCount >= 2) {
      return 'Có lẽ đây là nơi bắt đầu của các chuyến hành trình!';
    }
    if (stats.distanceKm >= 50) {
      return 'Cung đường quen thuộc mà lần nào chạy cũng thấy mê!';
    }
    if (stats.waypointCount >= 5) {
      return 'Quá trời điểm check-in ở đây luôn, đi tới đâu cũng có kỷ niệm!';
    }
    return null;
  }

  /// Friendly note for Monthly Statistics based on month performance.
  static String pickMonthlyQuote({
    required MonthlyStats? stats,
    required int year,
    required int month,
    Random? random,
  }) {
    if (stats == null || stats.tripCount == 0) {
      return 'Tháng $month/$year vẫn còn bỏ ngỏ nè — tụi mình làm một vòng hóng gió mở hàng đi thôi!';
    }

    final km = stats.totalDistanceKm;
    final candidates = <String>[];

    if (km >= 150) {
      candidates.add(
        'Tháng $month tụi mình lăn bánh tới ${km.toStringAsFixed(1)} km qua ${stats.tripCount} chuyến — đúng chất đôi bạn không biết mệt!',
      );
      candidates.add(
        'Hơn ${km.toStringAsFixed(0)} km rồi đó bạn ơi! Giữ phong độ để phá kỷ lục tháng trước nha.',
      );
    } else if (km >= 30) {
      candidates.add(
        'Đã đi được ${km.toStringAsFixed(1)} km với ${stats.tripCount} chuyến trong tháng $month — đều đặn mà chất lượng lắm luôn!',
      );
    } else {
      candidates.add(
        'Tháng $month mới khởi động nhẹ ${km.toStringAsFixed(1)} km nè, cuối tuần làm thêm một chuyến xa hơn chút nhé!',
      );
    }

    if (stats.waypointCount >= 3) {
      candidates.add(
        'Ghé tới ${stats.waypointCount} điểm dừng đáng nhớ trong tháng $month rồi, tụi mình đúng kiểu thích dừng đâu là khám phá tới đó!',
      );
    }

    final rng = random ?? Random(stats.tripCount + month);
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Friendly note for Photo Discovery screen.
  static String pickPhotoQuote({
    required int totalPhotos,
    required int provinceCount,
    Random? random,
  }) {
    if (totalPhotos == 0) {
      return 'Chuyến nào thấy cảnh đẹp nhớ chụp lại, tụi mình gom hết thành bản đồ kỷ niệm ở đây nha!';
    }

    final regionCount = provinceCount > 0 ? provinceCount : 1;
    final candidates = <String>[
      '$totalPhotos bức ảnh qua $regionCount vùng đất — nhìn lại mới thấy tụi mình đi qua nhiều góc đẹp thật đấy!',
      'Mỗi tấm ảnh là một lần tụi mình dừng xe ngắm cảnh, cùng lưu thêm thật nhiều khoảnh khắc nữa nhé!',
      if (totalPhotos >= 10)
        'Bộ sưu tập lên tới $totalPhotos ảnh rồi nè — sau này mở lại chắc chắn nhớ từng con đường luôn!',
    ];

    final rng = random ?? Random(totalPhotos + provinceCount);
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Friendly note for Trips History screen.
  static String pickHistoryQuote({
    required List<Trip> trips,
    Random? random,
  }) {
    if (trips.isEmpty) {
      return 'Quyển nhật ký hành trình đang chờ trang đầu tiên của tụi mình đó!';
    }

    final homeCount = countHomeTrips(trips);
    final candidates = <String>[
      if (homeCount >= 2)
        'Có $homeCount chuyến bắt đầu hoặc trở về Nhà — có lẽ đây là nơi bắt đầu của mọi chuyến hành trình!',
      if (homeCount >= 1)
        'Đi xa mấy rồi cuối ngày cũng về tới Nhà — xem lại ${trips.length} cung đường đã qua nhé!',
      '${trips.length} chuyến đi là từng đó kỷ niệm trên đường — mỗi vệt sáng là một ngày vui!',
      'Thỉnh thoảng mở lại mấy chuyến cũ để nhớ tụi mình đã cùng nhau đi xa tới đâu nha!',
    ];

    final rng = random ?? Random(trips.length + homeCount);
    return candidates[rng.nextInt(candidates.length)];
  }
}
