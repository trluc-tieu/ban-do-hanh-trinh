import 'trip.dart';

class MonthlyStats {
  final int year;
  final int month;
  final double totalDistanceKm;
  final double newDistanceKm;
  final int tripCount;
  final int totalDurationSeconds;
  final double avgSpeedKmh;
  final int waypointCount;
  final List<Trip> trips;
  final Map<int, double> distanceByDay; // day of month -> distance in km
  final Map<int, double> newDistanceByDay; // day of month -> newly explored km

  MonthlyStats({
    required this.year,
    required this.month,
    required this.totalDistanceKm,
    this.newDistanceKm = 0.0,
    required this.tripCount,
    required this.totalDurationSeconds,
    required this.avgSpeedKmh,
    required this.waypointCount,
    required this.trips,
    required this.distanceByDay,
    Map<int, double>? newDistanceByDay,
  }) : newDistanceByDay = newDistanceByDay ?? const {};

  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours giờ $minutes phút';
    }
    return '$minutes phút';
  }

  String get monthNameVi {
    return 'Tháng $month/$year';
  }

  factory MonthlyStats.calculate(int year, int month, List<Trip> monthTrips, int waypoints) {
    double totalDist = 0.0;
    double newDist = 0.0;
    int totalDur = 0;
    double speedSum = 0.0;
    final Map<int, double> byDay = {};
    final Map<int, double> newByDay = {};

    // Initialize days of month
    final daysInMonth = DateTime(year, month + 1, 0).day;
    for (int d = 1; d <= daysInMonth; d++) {
      byDay[d] = 0.0;
      newByDay[d] = 0.0;
    }

    for (final trip in monthTrips) {
      totalDist += trip.distanceKm;
      newDist += trip.newDistanceKm;
      totalDur += trip.durationSeconds;
      speedSum += trip.avgSpeedKmh;

      final day = trip.startTime.day;
      byDay[day] = (byDay[day] ?? 0.0) + trip.distanceKm;
      newByDay[day] = (newByDay[day] ?? 0.0) + trip.newDistanceKm;
    }

    final avgSpd = monthTrips.isNotEmpty ? (speedSum / monthTrips.length) : 0.0;

    return MonthlyStats(
      year: year,
      month: month,
      totalDistanceKm: totalDist,
      newDistanceKm: newDist,
      tripCount: monthTrips.length,
      totalDurationSeconds: totalDur,
      avgSpeedKmh: avgSpd,
      waypointCount: waypoints,
      trips: monthTrips,
      distanceByDay: byDay,
      newDistanceByDay: newByDay,
    );
  }
}
