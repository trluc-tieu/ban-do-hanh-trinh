import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/track_point.dart';
import '../models/trip.dart';
import '../models/vehicle_type.dart';
import '../models/waypoint.dart';
import '../providers/trip_provider.dart';
import '../services/database_service.dart';
import '../services/exploration_calculator.dart';
import '../services/external_map_service.dart';
import '../theme/app_theme.dart';
import '../widgets/goong_map_widget.dart';
import '../widgets/metric_card.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Trip? _trip;
  TripSegmentBreakdown? _breakdown;
  bool _isLoading = true;
  int _scrubberIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadTripData();
  }

  Future<void> _loadTripData() async {
    final db = DatabaseService();
    final trip = await db.getTrip(widget.tripId);
    TripSegmentBreakdown? breakdown;

    if (trip != null && trip.points.length >= 2) {
      final allTrips = await db.getAllTrips();
      final allRoutes = await db.getAllExploredRoutes();
      final priorIndex = ExplorationIndex();

      final chronological = List<Trip>.from(allTrips)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      for (final other in chronological) {
        if (other.id == trip.id) break;
        if (!other.startTime.isBefore(trip.startTime)) continue;
        final pts = allRoutes[other.id];
        if (pts != null && pts.length >= 2) {
          priorIndex.addTripPoints(pts);
        }
      }

      breakdown = priorIndex.classifyTripSegments(trip.points);
      final clampedNew = trip.totalDistance > 0
          ? breakdown.newMeters.clamp(0.0, trip.totalDistance)
          : breakdown.newMeters;
      trip.newDistance = clampedNew;
    }

    if (!mounted) return;
    setState(() {
      _trip = trip;
      _breakdown = breakdown;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chi tiết hành trình')),
        body: const Center(child: Text('Không tìm thấy thông tin chuyến đi')),
      );
    }

    final points = _trip!.points;
    final waypoints = _trip!.waypoints;
    String dateStr;
    try {
      dateStr = DateFormat('HH:mm • EEEE, dd/MM/yyyy', 'vi').format(_trip!.startTime);
    } catch (_) {
      dateStr = DateFormat('HH:mm • dd/MM/yyyy').format(_trip!.startTime);
    }

    final LatLng? startLatLng = points.isNotEmpty
        ? LatLng(points.first.latitude, points.first.longitude)
        : null;
    final LatLng? endLatLng = points.isNotEmpty
        ? LatLng(points.last.latitude, points.last.longitude)
        : null;
    TrackPoint? scrubPoint;
    LatLng? currentScrubLatLng;

    if (points.isNotEmpty) {
      final safeIdx = _scrubberIndex.clamp(0, points.length - 1);
      scrubPoint = points[safeIdx];
      currentScrubLatLng = LatLng(scrubPoint.latitude, scrubPoint.longitude);
    }

    // Derive ordered sequence of vehicles used across recorded points (falls back to trip.vehicleTypesUsed)
    final List<VehicleType> timelineVehicles = [];
    for (final pt in points) {
      if (timelineVehicles.isEmpty || timelineVehicles.last != pt.vehicleType) {
        timelineVehicles.add(pt.vehicleType);
      }
    }
    if (timelineVehicles.isEmpty) {
      timelineVehicles.addAll(_trip!.vehicleTypesUsed);
    }
    final activeScrubVehicle = scrubPoint?.vehicleType ?? _trip!.vehicleType;

    final size = MediaQuery.of(context).size;
    final isCompactLandscape = size.width > size.height && size.height < 520;

    final mapSection = Stack(
      children: [
        GoongMapWidget(
          center: startLatLng,
          initialZoom: 14.5,
          activePoints: points,
          newRoutePolylines: _breakdown?.newPolylines,
          repeatedRoutePolylines: _breakdown?.repeatedPolylines,
          waypoints: waypoints,
          startPoint: startLatLng,
          endPoint: endLatLng,
          highlightedPoint: currentScrubLatLng,
          highlightedVehicleType: activeScrubVehicle,
          controlsBottomOffset: points.length > 1 ? 104.0 : 16.0,
        ),

        // Legend overlay showing newly explored vs already-explored road colors
        if (_breakdown != null)
          Positioned(
            top: 10,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Mới +${_trip!.newDistanceKm.toStringAsFixed(2)} km',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  if (_trip!.repeatedDistanceKm >= 0.01) ...[
                    const SizedBox(width: 10),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF64748B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Đã đi ${_trip!.repeatedDistanceKm.toStringAsFixed(2)} km',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Scrubber overlay card
        if (points.length > 1)
          Positioned(
            left: 14,
            right: 14,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.94),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(activeScrubVehicle.icon, size: 13, color: AppTheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  activeScrubVehicle.label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Điểm ${_scrubberIndex + 1}/${points.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      if (scrubPoint != null)
                        Flexible(
                          child: Text(
                            '${scrubPoint.speedKmh.toStringAsFixed(1)} km/h • ${DateFormat('HH:mm:ss').format(scrubPoint.timestamp)}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Slider(
                    value: _scrubberIndex.toDouble(),
                    min: 0,
                    max: (points.length - 1).toDouble(),
                    divisions: points.length > 1 ? points.length - 1 : 1,
                    activeColor: AppTheme.primary,
                    onChanged: (val) {
                      setState(() {
                        _scrubberIndex = val.toInt();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    final detailsSection = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        // Vehicle timeline summary chip(s)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Phương tiện:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            for (int i = 0; i < timelineVehicles.length; i++) ...[
              if (i > 0)
                const Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.grey),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(timelineVehicles[i].icon, size: 14, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      timelineVehicles[i].label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Address info if available
        if (_trip!.startAddress != null || _trip!.endAddress != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_trip!.startAddress != null)
                  InkWell(
                    onTap: startLatLng != null
                        ? () => ExternalMapService().openGoogleMaps(
                              startLatLng.latitude,
                              startLatLng.longitude,
                              label: _trip!.startAddress,
                            )
                        : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.trip_origin, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bắt đầu: ${_trip!.startAddress}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Icon(Icons.open_in_new, size: 12, color: Colors.grey),
                      ],
                    ),
                  ),
                if (_trip!.endAddress != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: endLatLng != null
                        ? () => ExternalMapService().openGoogleMaps(
                              endLatLng.latitude,
                              endLatLng.longitude,
                              label: _trip!.endAddress,
                            )
                        : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kết thúc: ${_trip!.endAddress}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Icon(Icons.open_in_new, size: 12, color: Colors.grey),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Metric Grid
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Khám phá mới (${_trip!.newDiscoveryPercent.round()}%)',
                value: _trip!.newDistanceKm.toStringAsFixed(2),
                unit: 'km',
                icon: Icons.explore_rounded,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                title: 'Chiều dài chuyến đi',
                value: _trip!.distanceKm.toStringAsFixed(2),
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
                title: 'Thời lượng',
                value: _trip!.formattedDuration,
                unit: '',
                icon: Icons.timer_outlined,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                title: 'Tốc độ TB • Cao nhất',
                value: '${_trip!.avgSpeedKmh.toStringAsFixed(1)} • ${_trip!.maxSpeedKmh.toStringAsFixed(1)}',
                unit: 'km/h',
                icon: Icons.speed_rounded,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Waypoints list section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Điểm đến đã khám phá (${waypoints.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (waypoints.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Text(
              'Chưa có điểm mốc check-in trong chuyến đi này',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          )
        else
          ...waypoints.map((wp) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.star, color: Colors.orange, size: 20),
                  ),
                  title: Text(wp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(wp.note ?? 'Toạ độ: ${wp.latitude.toStringAsFixed(4)}, ${wp.longitude.toStringAsFixed(4)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.map_outlined, color: Colors.blueAccent, size: 20),
                        tooltip: 'Xem trên Google Maps',
                        onPressed: () => ExternalMapService().openGoogleMaps(
                          wp.latitude,
                          wp.longitude,
                          label: wp.name,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined, color: Colors.teal, size: 20),
                        tooltip: 'Xem ảnh Google Photos',
                        onPressed: () => ExternalMapService().openGooglePhotos(
                          lat: wp.latitude,
                          lng: wp.longitude,
                          timestamp: wp.timestamp,
                          placeName: wp.name,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _showWaypointActions(context, wp),
                ),
              )),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isCompactLandscape ? 46 : null,
        title: Text(_trip!.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Xoá chuyến đi',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: isCompactLandscape
          ? Row(
              children: [
                Expanded(flex: 5, child: mapSection),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(flex: 5, child: detailsSection),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 5, child: mapSection),
                Expanded(flex: 5, child: detailsSection),
              ],
            ),
    );
  }

  void _showWaypointActions(BuildContext context, Waypoint wp) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.orange, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      wp.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (wp.note != null && wp.note!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(wp.note!, style: const TextStyle(color: Colors.black87, fontSize: 13)),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.map_rounded, color: Colors.blue),
                title: const Text('Xem vị trí trên Google Maps'),
                subtitle: const Text('Mở vị trí chính xác trên ứng dụng Google Maps'),
                onTap: () {
                  Navigator.pop(ctx);
                  ExternalMapService().openGoogleMaps(wp.latitude, wp.longitude, label: wp.name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_back_rounded, color: Colors.teal),
                title: const Text('Xem ảnh trên Google Photos'),
                subtitle: const Text('Tìm ảnh chụp tại toạ độ này hoặc thời gian này'),
                onTap: () {
                  Navigator.pop(ctx);
                  ExternalMapService().openGooglePhotos(
                    lat: wp.latitude,
                    lng: wp.longitude,
                    timestamp: wp.timestamp,
                    placeName: wp.name,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.indigo),
                title: const Text('Mở thư viện ảnh trên máy'),
                subtitle: const Text('Xem toàn bộ ảnh trên thiết bị của bạn'),
                onTap: () {
                  Navigator.pop(ctx);
                  ExternalMapService().openDeviceGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá hành trình này?'),
        content: const Text('Hành trình này sẽ bị xoá vĩnh viễn khỏi lịch sử và bản đồ khám phá.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await Provider.of<TripProvider>(context, listen: false).deleteTrip(widget.tripId);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Xoá', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
