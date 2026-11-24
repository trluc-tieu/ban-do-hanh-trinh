import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_type.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/trip_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_waypoint_dialog.dart';
import '../widgets/goong_map_widget.dart';
import '../widgets/pending_stay_dialog.dart';
import '../widgets/vehicle_picker_sheet.dart';
import 'settings_screen.dart';
import 'trip_detail_screen.dart';

/// Unified Map & Live Exploration screen (Tab 1):
/// - Renders all historical explored routes AND continuously draws the live active polyline while moving.
/// - Updates unlocked km & traveled km in real time ONLY while actively recording (conserves battery when idle).
/// - Automatically hides check-in & photo pins while recording and restores them when stopped.
/// - Minimalist circular Play/Stop button + circular Vehicle icon picker button.
class DiscoveryMapScreen extends StatefulWidget {
  const DiscoveryMapScreen({super.key});

  @override
  State<DiscoveryMapScreen> createState() => _DiscoveryMapScreenState();
}

class _DiscoveryMapScreenState extends State<DiscoveryMapScreen> {
  bool _showWaypoints = true;

  String _getExplorerTitle(double totalKm) {
    if (totalKm < 10) return 'Tân Binh Khám Phá';
    if (totalKm < 50) return 'Nhà Du Hành Phố Thị';
    if (totalKm < 150) return 'Phượt Thủ Dày Dạn';
    if (totalKm < 500) return 'Bậc Thầy Cung Đường';
    return 'Huyền Thoại Khám Phá';
  }

  Future<void> _onPlayPressed(BuildContext context) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    if (tracking.isRecording || tracking.isStarting) return;
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    tracking.setPinnedPlaces(tripProvider.pinnedPlaces);
    final success = await tracking.startTracking(
      distanceFilter: settings.distanceFilter,
      autoStop: settings.autoStopWhenStationary,
      autoStopMins: settings.autoStopStationaryMinutes,
      homeLat: settings.homeLat,
      homeLng: settings.homeLng,
      homeRadiusMeters: settings.homeRadiusMeters,
      vehicleType: settings.vehicleType,
      priorRoutes: tripProvider.allExplorationRoutes,
    );

    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng cấp quyền vị trí GPS để bắt đầu ghi hành trình.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _onStopPressed(BuildContext context) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    tracking.setHomeConfig(
      lat: settings.homeLat,
      lng: settings.homeLng,
      radiusMeters: settings.homeRadiusMeters,
    );
    tracking.setPinnedPlaces(tripProvider.pinnedPlaces);

    final completedTrip = await tracking.stopTracking();
    if (completedTrip != null) {
      await tripProvider.refreshAll();
      if (!context.mounted) return;

      final savedTrip = tripProvider.trips.cast<dynamic>().firstWhere(
            (t) => t.id == completedTrip.id,
            orElse: () => completedTrip,
          );
      final double tripKm = savedTrip.distanceKm as double;
      final double newKm = savedTrip.newDistanceKm as double;
      final double repeatedKm = savedTrip.repeatedDistanceKm as double;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 28),
              SizedBox(width: 8),
              Expanded(child: Text('Hoàn thành chuyến đi!')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Khám phá mới: +${newKm.toStringAsFixed(2)} km!',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text('Chuyến đi dài: ${tripKm.toStringAsFixed(2)} km'),
              if (repeatedKm >= 0.01)
                Text(
                  'Đường đã đi trước đó: ${repeatedKm.toStringAsFixed(2)} km',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              Text(
                'Tổng đã khám phá: ${tripProvider.uniqueExploredKm.toStringAsFixed(2)} km',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Icon(completedTrip.vehicleType.icon, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Phương tiện: ${completedTrip.vehicleSummaryLabel}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Thời gian: ${completedTrip.formattedDuration}'),
              Text('Vận tốc TB: ${completedTrip.avgSpeedKmh.toStringAsFixed(1)} km/h'),
              Text('Điểm đã đến: ${completedTrip.waypoints.length} mốc'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripDetailScreen(tripId: completedTrip.id),
                  ),
                );
              },
              child: const Text('Xem chi tiết'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _onAddWaypoint(BuildContext context) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddWaypointDialog(
        initialLat: tracking.currentPosition?.latitude,
        initialLng: tracking.currentPosition?.longitude,
      ),
    );

    if (result != null && result['name'] != null) {
      final wp = await tracking.addWaypoint(
        result['name'] as String,
        note: result['note'] as String?,
        latitude: result['latitude'] as double?,
        longitude: result['longitude'] as double?,
      );
      if (wp != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã đánh dấu điểm đến: ${wp.name}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);
    final tracking = Provider.of<TrackingProvider>(context);
    final settings = Provider.of<MapSettingsProvider>(context);
    final size = MediaQuery.of(context).size;
    final isCompactLandscape = size.width > size.height && size.height < 520;

    final isRecording = tracking.isRecording;

    // Real-time distance totals (only accumulate active session when recording!)
    final liveUniqueKm =
        tripProvider.uniqueExploredKm + (isRecording ? tracking.currentNewDistanceKm : 0.0);
    final liveTraveledKm =
        tripProvider.totalTraveledKm + (isRecording ? tracking.currentDistanceKm : 0.0);

    final routes = tripProvider.allExplorationRoutes;
    // Automatically hide check-in & photo pins while moving/recording; restore when stopped!
    final visibleWaypoints = (!isRecording && _showWaypoints) ? tripProvider.allWaypoints : null;

    LatLng? userLatLng;
    if (tracking.currentPosition != null) {
      userLatLng = LatLng(
        tracking.currentPosition!.latitude,
        tracking.currentPosition!.longitude,
      );
    }

    LatLng? initialCenter = userLatLng;
    if (initialCenter == null && routes.isNotEmpty) {
      final firstTripPoints = routes.values.first;
      if (firstTripPoints.isNotEmpty) {
        initialCenter = LatLng(
          firstTripPoints.first.latitude,
          firstTripPoints.first.longitude,
        );
      }
    }

    final topCardOffset = isCompactLandscape ? 50.0 : 94.0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isCompactLandscape ? 46 : null,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.explore_rounded, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Bản Đồ Hành Trình',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          if (!isRecording)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _showWaypoints ? Icons.pin_drop_rounded : Icons.pin_drop_outlined,
                color: _showWaypoints ? Colors.orange : null,
              ),
              tooltip: _showWaypoints ? 'Ẩn điểm check-in & ảnh' : 'Hiện điểm check-in & ảnh',
              onPressed: () => setState(() => _showWaypoints = !_showWaypoints),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              settings.backgroundAutoTrack
                  ? Icons.directions_run_rounded
                  : Icons.bedtime_outlined,
              color: settings.backgroundAutoTrack ? AppTheme.primary : null,
            ),
            tooltip: settings.backgroundAutoTrack
                ? 'Chạy ngầm tự động ghi: ĐANG BẬT'
                : 'Bật chạy ngầm tự động ghi hành trình',
            onPressed: () {
              final next = !settings.backgroundAutoTrack;
              settings.setBackgroundAutoTrack(next);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(
                    next
                        ? 'Đã BẬT tự động ghi hành trình chạy ngầm (>= ${settings.autoTrackMinSpeedKmh.toInt()} km/h).'
                        : 'Đã TẮT chạy ngầm để tối ưu tiết kiệm pin.',
                  ),
                ),
              );
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
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
      body: Stack(
        children: [
          // Unified Map rendering BOTH historical explored routes AND live growing polyline!
          GoongMapWidget(
            center: initialCenter,
            userLocation: userLatLng,
            initialZoom: 15.0,
            showExplorationMode: true,
            explorationRoutes: routes,
            activePoints: isRecording ? tracking.currentPoints : null,
            waypoints: visibleWaypoints,
            hasLiveFix: tracking.hasLiveFix,
            isVehicleMode: isRecording,
            movementHeading: tracking.courseHeading,
            autoFollowUser: isRecording,
            controlsBottomOffset: isCompactLandscape ? 14.0 : 90.0,
          ),

          // Top Real-Time Summary / Live Status Overlay
          Positioned(
            top: isCompactLandscape ? 8 : 10,
            left: isCompactLandscape ? 12 : 14,
            right: isCompactLandscape ? null : 14,
            child: isRecording
                ? _buildLiveTopBanner(tracking, liveUniqueKm, compact: isCompactLandscape)
                : _buildIdleTopBanner(
                    tripProvider,
                    liveUniqueKm,
                    liveTraveledKm,
                    compact: isCompactLandscape,
                  ),
          ),

          // Notification banners (Pending Stay / Auto-Start / Auto-Stop)
          if (tracking.pendingStayPoints.isNotEmpty)
            Positioned(
              top: topCardOffset,
              left: isCompactLandscape ? 12 : 14,
              right: isCompactLandscape ? null : 14,
              width: isCompactLandscape ? 320 : null,
              child: GestureDetector(
                onTap: () => PendingStayDialog.show(context, tracking.pendingStayPoints.first),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Phát hiện ${tracking.pendingStayPoints.length} điểm dừng chân! Chạm xác nhận.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 13),
                    ],
                  ),
                ),
              ),
            )
          else if (tracking.lastAutoStartedMessage != null ||
              tracking.lastAutoStoppedMessage != null)
            Positioned(
              top: topCardOffset,
              left: isCompactLandscape ? 12 : 14,
              right: isCompactLandscape ? null : 14,
              width: isCompactLandscape ? 320 : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: tracking.lastAutoStartedMessage != null
                      ? AppTheme.primary
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    Icon(
                      tracking.lastAutoStartedMessage != null
                          ? Icons.directions_run_rounded
                          : Icons.timer_off_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tracking.lastAutoStartedMessage ?? tracking.lastAutoStoppedMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        if (tracking.lastAutoStartedMessage != null) {
                          tracking.dismissAutoStartMessage();
                        } else {
                          tracking.dismissAutoStopMessage();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Minimalist Circular Bottom Controls: Vehicle Picker + Play/Stop (+ Pause & Check-in when recording)
          Positioned(
            bottom: isCompactLandscape ? 14 : 18,
            left: isCompactLandscape ? 14 : 0,
            right: isCompactLandscape ? null : 0,
            child: Center(
              child: _buildCircularBottomControls(context, tracking, settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleTopBanner(
    TripProvider tripProvider,
    double uniqueKm,
    double traveledKm, {
    required bool compact,
  }) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.discoveryNeon.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.military_tech_rounded, color: Colors.amber, size: 17),
            const SizedBox(width: 6),
            Text(
              _getExplorerTitle(uniqueKm),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(width: 10),
            Text(
              '• Khám phá ${uniqueKm.toStringAsFixed(1)} km (tổng ${traveledKm.toStringAsFixed(1)} km) • ${tripProvider.trips.length} chuyến',
              style: const TextStyle(
                color: AppTheme.discoveryNeon,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.discoveryNeon.withValues(alpha: 0.38), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.military_tech_rounded, color: Colors.amber, size: 19),
                  const SizedBox(width: 6),
                  Text(
                    _getExplorerTitle(uniqueKm),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                '${tripProvider.trips.length} cung đường • ${tripProvider.allWaypoints.length} mốc',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniMetric('ĐÃ KHÁM PHÁ', '${uniqueKm.toStringAsFixed(2)} km', AppTheme.discoveryNeon),
              _miniMetric('TỔNG ĐI', '${traveledKm.toStringAsFixed(2)} km', Colors.cyanAccent),
              _miniMetric(
                'THỜI GIAN',
                '${tripProvider.totalExploredHours.toStringAsFixed(1)} giờ',
                Colors.lightGreenAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTopBanner(
    TrackingProvider tracking,
    double liveUniqueKm, {
    required bool compact,
  }) {
    final statusColor = tracking.isPaused ? Colors.amber : Colors.greenAccent;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 7 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.65), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fiber_manual_record, size: 11, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  tracking.formattedDuration,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(width: 10),
                Text(
                  'Chuyến ${tracking.currentDistanceKm.toStringAsFixed(2)} km (+${tracking.currentNewDistanceKm.toStringAsFixed(2)} mới) • Tổng ${liveUniqueKm.toStringAsFixed(2)} km • ${tracking.currentSpeedKmh.toStringAsFixed(1)} km/h',
                  style: const TextStyle(
                    color: AppTheme.discoveryNeon,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tracking.isPaused ? 'TẠM DỪNG' : 'ĐANG DI CHUYỂN (ẨN GHIM ẢNH/MỐC)',
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Tổng mở khoá: ${liveUniqueKm.toStringAsFixed(2)} km',
                      style: const TextStyle(
                        color: AppTheme.discoveryNeon,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniMetric('THỜI GIAN', tracking.formattedDuration, Colors.white),
                    _miniMetric(
                      'CHUYẾN NÀY',
                      '${tracking.currentDistanceKm.toStringAsFixed(2)} km',
                      Colors.cyanAccent,
                    ),
                    _miniMetric(
                      'MỚI MỞ KHOÁ',
                      '+${tracking.currentNewDistanceKm.toStringAsFixed(2)} km',
                      AppTheme.discoveryNeon,
                    ),
                    _miniMetric(
                      'TỐC ĐỘ',
                      '${tracking.currentSpeedKmh.toStringAsFixed(1)} km/h',
                      AppTheme.accent,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildCircularBottomControls(
    BuildContext context,
    TrackingProvider tracking,
    MapSettingsProvider settings,
  ) {
    final isRecording = tracking.isRecording;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular Vehicle Icon Picker (tap anytime — idle or mid-ride!)
          Tooltip(
            message: 'Đổi phương tiện (Đang chọn: ${settings.vehicleType.label})',
            child: InkWell(
              onTap: () => VehiclePickerSheet.show(context),
              customBorder: const CircleBorder(),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: settings.vehicleColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: settings.vehicleColor, width: 2),
                ),
                child: Icon(
                  settings.vehicleType.icon,
                  color: settings.vehicleColor,
                  size: 24,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Main Circular Play / Stop Button
          Tooltip(
            message: isRecording ? 'Kết thúc & Lưu hành trình' : 'Bắt đầu ghi hành trình',
            child: InkWell(
              onTap: tracking.isStarting
                  ? null
                  : () => isRecording ? _onStopPressed(context) : _onPlayPressed(context),
              customBorder: const CircleBorder(),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isRecording ? Colors.redAccent : AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isRecording ? Colors.redAccent : AppTheme.primary)
                          .withValues(alpha: 0.42),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: tracking.isStarting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Icon(
                        isRecording ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: isRecording ? 34 : 38,
                      ),
              ),
            ),
          ),

          // Compact round Pause/Resume & Check-in buttons while actively recording
          if (isRecording) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: tracking.isPaused ? 'Tiếp tục ghi' : 'Tạm dừng',
              child: InkWell(
                onTap: () => tracking.isPaused
                    ? tracking.resumeTracking()
                    : tracking.pauseTracking(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amber.shade700, width: 1.8),
                  ),
                  child: Icon(
                    tracking.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.amber.shade800,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Check-in điểm đến nhanh',
              child: InkWell(
                onTap: () => _onAddWaypoint(context),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.shade700, width: 1.8),
                  ),
                  child: Icon(
                    Icons.add_location_alt_rounded,
                    color: Colors.orange.shade800,
                    size: 21,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: Colors.white60, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
