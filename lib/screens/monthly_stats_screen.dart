import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../services/companion_quotes.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/monthly_bar_chart.dart';
import '../widgets/trip_card.dart';
import 'settings_screen.dart';
import 'trip_detail_screen.dart';

class MonthlyStatsScreen extends StatelessWidget {
  const MonthlyStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);
    final stats = tripProvider.currentMonthlyStats;
    final selectedYear = tripProvider.selectedYear;
    final selectedMonth = tripProvider.selectedMonth;

    final daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê khám phá'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cài đặt',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          // Month navigation bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppTheme.primary),
                  tooltip: 'Tháng trước',
                  onPressed: () => tripProvider.previousMonth(),
                ),
                Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Tháng $selectedMonth / $selectedYear',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppTheme.primary),
                  tooltip: 'Tháng sau',
                  onPressed: () => tripProvider.nextMonth(),
                ),
              ],
            ),
          ),

          // Friendly companion observation based on this month's stats
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    CompanionQuotes.pickMonthlyQuote(
                      stats: stats,
                      year: selectedYear,
                      month: selectedMonth,
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (stats == null || stats.tripCount == 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MonthlyBarChart(
                distanceByDay: const {},
                daysInMonth: daysInMonth,
              ),
            ),
            const SizedBox(height: 36),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.explore_off_outlined,
                      size: 64,
                      color: Colors.grey.withOpacity(0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Không có dữ liệu trong Tháng $selectedMonth/$selectedYear',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bạn chưa có chuyến đi nào trong tháng này. Hãy nhấn "Bắt đầu" để lập kỷ lục mới!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Monthly Metric Cards Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: 'Khám phá mới',
                          value: stats.newDistanceKm.toStringAsFixed(1),
                          unit: 'km',
                          icon: Icons.explore_rounded,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricCard(
                          title: 'Tổng quãng đường',
                          value: stats.totalDistanceKm.toStringAsFixed(1),
                          unit: 'km',
                          icon: Icons.straighten_rounded,
                          color: Colors.cyan.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: 'Số chuyến đi',
                          value: '${stats.tripCount}',
                          unit: 'chuyến',
                          icon: Icons.navigation_rounded,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricCard(
                          title: 'Vận tốc trung bình',
                          value: stats.avgSpeedKmh.toStringAsFixed(1),
                          unit: 'km/h',
                          icon: Icons.speed_rounded,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  MetricCard(
                    title: 'Thời gian di chuyển trong tháng',
                    value: stats.formattedDuration,
                    unit: '• ${stats.waypointCount} điểm check-in',
                    icon: Icons.schedule_rounded,
                    color: Colors.deepPurple,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Bar chart of daily exploration in this month
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MonthlyBarChart(
                distanceByDay: stats.distanceByDay,
                daysInMonth: daysInMonth,
              ),
            ),

            const SizedBox(height: 20),

            // Section: Trips in this month
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Các cung đường trong tháng (${stats.trips.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            ...stats.trips.map(
              (trip) => TripCard(
                trip: trip,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripDetailScreen(tripId: trip.id),
                    ),
                  );
                },
                onRename: (newTitle) {
                  tripProvider.updateTripTitle(trip.id, newTitle);
                },
                onDelete: () {
                  tripProvider.deleteTrip(trip.id);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
