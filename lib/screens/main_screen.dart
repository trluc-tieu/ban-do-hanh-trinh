import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/trip_provider.dart';
import '../theme/app_theme.dart';
import 'discovery_map_screen.dart';
import 'monthly_stats_screen.dart';
import 'photo_discovery_screen.dart';
import 'province_ranking_screen.dart';
import 'trips_history_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  String _lastSyncSignature = '';

  void _syncTrackingConfig(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    final tripProvider = Provider.of<TripProvider>(context);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);

    tracking.onTripCompletedCallback = () {
      tripProvider.refreshAll();
    };

    final sig = [
      settings.backgroundAutoTrack,
      settings.autoTrackMinSpeedKmh,
      settings.autoTrackMinRangeMeters,
      settings.autoStopWhenStationary,
      settings.autoStopStationaryMinutes,
      settings.distanceFilter,
      settings.vehicleType.index,
      settings.homeLat,
      settings.homeLng,
      settings.homeRadiusMeters,
      tripProvider.pinnedPlaces.length,
      tripProvider.allExplorationRoutes.length,
    ].join('|');

    if (sig != _lastSyncSignature) {
      _lastSyncSignature = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tracking.configureBackgroundMonitoring(
          enabled: settings.backgroundAutoTrack,
          minSpeedKmh: settings.autoTrackMinSpeedKmh,
          minRangeMeters: settings.autoTrackMinRangeMeters,
          autoStop: settings.autoStopWhenStationary,
          autoStopMins: settings.autoStopStationaryMinutes,
          distanceFilter: settings.distanceFilter,
          vehicleType: settings.vehicleType,
          homeLat: settings.homeLat,
          homeLng: settings.homeLng,
          homeRadiusMeters: settings.homeRadiusMeters,
          pinnedPlaces: tripProvider.pinnedPlaces,
          priorRoutes: tripProvider.allExplorationRoutes,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTrackingConfig(context);
    final size = MediaQuery.of(context).size;
    final isCompactLandscape = size.width > size.height && size.height < 520;

    final stackBody = IndexedStack(
      index: _currentIndex,
      children: const [
        DiscoveryMapScreen(),
        ProvinceRankingScreen(),
        PhotoDiscoveryScreen(),
        MonthlyStatsScreen(),
        TripsHistoryScreen(),
      ],
    );

    if (isCompactLandscape) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              minWidth: 64,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded, color: AppTheme.primary),
                  label: Text('Bản Đồ', style: TextStyle(fontSize: 10.5)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.military_tech_outlined),
                  selectedIcon: Icon(Icons.military_tech_rounded, color: AppTheme.primary),
                  label: Text('Khám Phá', style: TextStyle(fontSize: 10.5)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded, color: AppTheme.primary),
                  label: Text('Ảnh', style: TextStyle(fontSize: 10.5)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded, color: AppTheme.primary),
                  label: Text('Thống Kê', style: TextStyle(fontSize: 10.5)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history_rounded, color: AppTheme.primary),
                  label: Text('Lịch Sử', style: TextStyle(fontSize: 10.5)),
                ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: stackBody),
          ],
        ),
      );
    }

    return Scaffold(
      body: stackBody,
      bottomNavigationBar: NavigationBar(
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded, color: AppTheme.primary),
            label: 'Bản Đồ',
          ),
          NavigationDestination(
            icon: Icon(Icons.military_tech_outlined),
            selectedIcon: Icon(Icons.military_tech_rounded, color: AppTheme.primary),
            label: 'Khám Phá',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded, color: AppTheme.primary),
            label: 'Ảnh',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded, color: AppTheme.primary),
            label: 'Thống Kê',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded, color: AppTheme.primary),
            label: 'Lịch Sử',
          ),
        ],
      ),
    );
  }
}
