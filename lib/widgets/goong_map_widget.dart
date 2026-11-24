import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/pinned_place.dart';
import '../models/track_point.dart';
import '../models/vehicle_type.dart';
import '../models/waypoint.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/trip_provider.dart';
import '../services/compass_service.dart';
import '../services/external_map_service.dart';
import '../services/goong_service.dart';
import '../theme/app_theme.dart';
import 'home_picker_dialog.dart';
import 'offline_map_preload_dialog.dart';
import 'pinned_place_dialog.dart';
import 'user_location_marker.dart';
import 'vector_map_style_mixin.dart';
import 'vehicle_picker_sheet.dart';

class GoongMapWidget extends StatefulWidget {
  final LatLng? center;
  final double initialZoom;
  final List<TrackPoint>? activePoints;
  final List<List<LatLng>>? newRoutePolylines;
  final List<List<LatLng>>? repeatedRoutePolylines;
  final Map<String, List<TrackPoint>>? explorationRoutes;
  final List<Waypoint>? waypoints;
  final LatLng? userLocation;
  final bool hasLiveFix;
  final bool isVehicleMode;
  final double? movementHeading;
  final bool autoFollowUser;
  final bool showHomePin;
  final bool showExplorationMode;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final LatLng? highlightedPoint; // point selected during inspection replay
  final VehicleType? highlightedVehicleType; // vehicle active at highlighted replay point
  final bool showControls;
  final double controlsBottomOffset;
  final Function(MapController)? onMapReady;

  const GoongMapWidget({
    super.key,
    this.center,
    this.initialZoom = 15.0,
    this.activePoints,
    this.newRoutePolylines,
    this.repeatedRoutePolylines,
    this.explorationRoutes,
    this.waypoints,
    this.userLocation,
    this.hasLiveFix = false,
    this.isVehicleMode = false,
    this.movementHeading,
    this.autoFollowUser = false,
    this.showHomePin = true,
    this.showExplorationMode = false,
    this.startPoint,
    this.endPoint,
    this.highlightedPoint,
    this.highlightedVehicleType,
    this.showControls = true,
    this.controlsBottomOffset = 20.0,
    this.onMapReady,
  });

  @override
  State<GoongMapWidget> createState() => _GoongMapWidgetState();
}

class _GoongMapWidgetState extends State<GoongMapWidget>
    with VectorMapStyleMixin<GoongMapWidget> {
  late final MapController _mapController;
  bool _hasTileError = false;
  MapStyleType? _lastStyle;
  bool _hasCenteredOnFirstLocation = false;
  bool _hasCenteredOnLiveFix = false;
  bool _isFollowingUser = false;
  double _mapRotationDeg = 0.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _isFollowingUser = widget.autoFollowUser;
    CompassService().start();

    if (widget.onMapReady != null) {
      widget.onMapReady!(_mapController);
    }

    if (widget.userLocation != null) {
      _hasCenteredOnFirstLocation = true;
      if (widget.hasLiveFix) _hasCenteredOnLiveFix = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.userLocation == null) return;
        try {
          _mapController.move(widget.userLocation!, 16.5);
        } catch (_) {}
      });
    }
  }

  @override
  void didUpdateWidget(covariant GoongMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final loc = widget.userLocation;
    if (loc != null) {
      final firstFixArrived = !_hasCenteredOnFirstLocation;
      final liveFixArrived = widget.hasLiveFix && !_hasCenteredOnLiveFix;

      if (firstFixArrived || liveFixArrived) {
        _hasCenteredOnFirstLocation = true;
        if (widget.hasLiveFix) _hasCenteredOnLiveFix = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.userLocation == null) return;
          try {
            _mapController.move(widget.userLocation!, 16.5);
          } catch (_) {}
        });
      }
    }

    if (widget.autoFollowUser && !oldWidget.autoFollowUser) {
      _isFollowingUser = true;
      if (loc != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _moveToFollow(loc);
        });
      }
    } else if (!widget.autoFollowUser && oldWidget.autoFollowUser) {
      _isFollowingUser = false;
      if (_mapRotationDeg.abs() > 1.0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            _mapController.rotate(0.0);
          } catch (_) {}
        });
      }
    } else if (_isFollowingUser &&
        loc != null &&
        (loc != oldWidget.userLocation ||
            widget.movementHeading != oldWidget.movementHeading)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _moveToFollow(loc);
      });
    }
  }

  void _moveToFollow(LatLng target) {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    if (!settings.autoCenter) return;
    try {
      final currentZoom = _mapController.camera.zoom;
      final zoom = currentZoom < 15.5 ? 16.5 : currentZoom;
      final heading = widget.movementHeading;
      if (widget.isVehicleMode &&
          settings.rotateMapWithHeading &&
          heading != null) {
        _mapController.moveAndRotate(target, zoom, -heading);
      } else {
        _mapController.move(target, zoom);
      }
    } catch (_) {}
  }

  void _recenterOnUser() async {
    setState(() => _isFollowingUser = true);
    if (!widget.isVehicleMode) {
      final tracking = Provider.of<TrackingProvider>(context, listen: false);
      final fresh = await tracking.refreshCurrentLocationOnce();
      if (!mounted) return;
      if (fresh != null) {
        try {
          _mapController.move(LatLng(fresh.latitude, fresh.longitude), 16.5);
        } catch (_) {}
        return;
      }
    }
    if (widget.userLocation != null) {
      final settings = Provider.of<MapSettingsProvider>(context, listen: false);
      final heading = widget.movementHeading;
      try {
        if (widget.isVehicleMode &&
            settings.rotateMapWithHeading &&
            heading != null) {
          _mapController.moveAndRotate(widget.userLocation!, 16.5, -heading);
        } else {
          _mapController.move(widget.userLocation!, 16.5);
        }
      } catch (_) {}
    } else if (widget.center != null) {
      _mapController.move(widget.center!, 15.5);
    }
  }

  void _resetNorth() {
    try {
      _mapController.rotate(0.0);
    } catch (_) {}
  }

  void _showHomePinSheet(BuildContext context, MapSettingsProvider settings) {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.home_rounded, color: Color(0xFFF59E0B), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vị trí "Nhà" của bạn',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (settings.homeLat != null && settings.homeLng != null)
                          Text(
                            'Toạ độ: ${settings.homeLat!.toStringAsFixed(5)}, ${settings.homeLng!.toStringAsFixed(5)} • Bán kính ${settings.homeRadiusMeters}m',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_location_alt_outlined, color: AppTheme.primary),
                title: const Text('Điều chỉnh vị trí Nhà trên bản đồ'),
                onTap: () {
                  Navigator.pop(ctx);
                  HomePickerDialog.show(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Xoá ghim Nhà', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await settings.clearHome();
                  tracking.setHomeConfig(lat: null, lng: null);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinnedPlaceSheet(BuildContext context, PinnedPlace place) {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final color = place.category.color;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.16),
                    child: Icon(place.category.icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${place.category.label} • Bán kính ${place.radiusMeters}m',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (place.note != null && place.note!.isNotEmpty)
                          Text(place.note!, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map_outlined, color: Colors.blue),
                title: const Text('Mở trên Google Maps'),
                onTap: () {
                  Navigator.pop(ctx);
                  ExternalMapService().openGoogleMaps(
                    place.latitude,
                    place.longitude,
                    label: place.name,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_location_alt_outlined, color: AppTheme.primary),
                title: const Text('Chỉnh sửa địa điểm'),
                onTap: () {
                  Navigator.pop(ctx);
                  PinnedPlaceDialog.show(context, existingPlace: place);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Xoá địa điểm ghim', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await tripProvider.deletePinnedPlace(place.id);
                  tracking.setPinnedPlaces(tripProvider.pinnedPlaces);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _showStyleSelector(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Chọn kiểu bản đồ hiển thị',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'GOOGLE MAPS (TIẾNG VIỆT - KHUYÊN DÙNG)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.googleStreets,
                'Google Maps Đường Phố',
                'Hiển thị đường sá, địa danh tiếng Việt chi tiết nhất',
                Icons.map,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.googleHybrid,
                'Google Maps Vệ Tinh Lai (Hybrid)',
                'Ảnh vệ tinh thực tế kết hợp tên đường tiếng Việt',
                Icons.layers,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.googleSatellite,
                'Google Maps Vệ Tinh Thuần',
                'Ảnh chụp vệ tinh độ nét cao của Google',
                Icons.satellite_alt,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.googleTerrain,
                'Google Maps Địa Hình',
                'Hiển thị đồi núi, sông ngòi, độ cao địa lý',
                Icons.terrain,
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'OPENMAP.VN / NDAMAPS (BẢN ĐỒ VECTOR VIỆT NAM)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.openmapVn,
                'OpenMap.vn / NDAMaps (Ban ngày)',
                'Bản đồ Vector Việt Nam chuẩn địa chính (dùng API Key)',
                Icons.explore_outlined,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.openmapVnNight,
                'OpenMap.vn / NDAMaps (Ban đêm)',
                'Giao diện Vector tối ban đêm (night-v1)',
                Icons.dark_mode_outlined,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.openmapVnSatellite,
                'OpenMap.vn / NDAMaps (Vệ tinh)',
                'Bản đồ vệ tinh NDAMaps (satellite-v1)',
                Icons.satellite_alt_outlined,
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'BẢN ĐỒ MỞ QUỐC TẾ (ĐÃ TUÂN THỦ CHÍNH SÁCH)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.openStreetMap,
                'OpenStreetMap Tiêu Chuẩn',
                'Nguồn mở quốc tế (User-Agent tuân thủ chuẩn OSM)',
                Icons.public,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.osmHot,
                'OpenStreetMap Tiếng Việt (HOT)',
                'Bản đồ cộng đồng HOT hiển thị rõ địa danh',
                Icons.map_outlined,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.esriSatellite,
                'Ảnh Vệ Tinh ESRI World Imagery',
                'Ảnh chụp vệ tinh độ phân giải cao',
                Icons.satellite_alt_outlined,
              ),
              _styleTile(
                ctx,
                settings,
                MapStyleType.topo,
                'Bản Đồ Địa Hình (OpenTopoMap)',
                'Đường đồng mức, địa hình phượt/leo núi',
                Icons.landscape,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styleTile(
    BuildContext ctx,
    MapSettingsProvider settings,
    MapStyleType type,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = settings.mapStyle == type;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.primary : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppTheme.primary : null,
          fontSize: 14,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
      onTap: () {
        setState(() {
          _hasTileError = false;
        });
        settings.setMapStyle(type);
        Navigator.pop(ctx);
      },
    );
  }

  String _getStyleErrorMessage(MapStyleType style) {
    switch (style) {
      case MapStyleType.googleStreets:
      case MapStyleType.googleHybrid:
      case MapStyleType.googleSatellite:
      case MapStyleType.googleTerrain:
        return 'Không tải được ô bản đồ Google Maps (Kiểm tra kết nối mạng).';
      case MapStyleType.openmapVn:
      case MapStyleType.openmapVnNight:
      case MapStyleType.openmapVnSatellite:
        return vectorError ?? 'Không tải được bản đồ Vector OpenMap.vn / NDAMaps.';
      case MapStyleType.openStreetMap:
      case MapStyleType.osmHot:
        return 'Không tải được OpenStreetMap (Kiểm tra mạng hoặc giới hạn tốc độ tải).';
      case MapStyleType.esriSatellite:
        return 'Không tải được ảnh Vệ Tinh ESRI (Kiểm tra kết nối mạng).';
      case MapStyleType.topo:
        return 'Không tải được bản đồ Địa Hình (Kiểm tra kết nối mạng).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    final fallbackCenter = widget.center ??
        widget.userLocation ??
        const LatLng(21.028511, 105.854444); // Hanoi center default

    // Polylines list
    final List<Polyline> polylines = [];

    // 1. Add all historical explored routes if in exploration mode
    if (widget.showExplorationMode && widget.explorationRoutes != null) {
      widget.explorationRoutes!.forEach((tripId, points) {
        if (points.length >= 2) {
          final latLngList = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
          polylines.add(
            Polyline(
              points: latLngList,
              strokeWidth: 4.5,
              color: AppTheme.discoveryNeon.withOpacity(0.85),
            ),
          );
        }
      });
    }

    // 2. Add trip polylines (either breakdown new vs repeated, or plain active polyline)
    final hasBreakdown =
        (widget.newRoutePolylines != null && widget.newRoutePolylines!.isNotEmpty) ||
        (widget.repeatedRoutePolylines != null && widget.repeatedRoutePolylines!.isNotEmpty);

    if (hasBreakdown) {
      // Previously explored (repeated) road segments rendered in cool slate-blue
      if (widget.repeatedRoutePolylines != null) {
        for (final span in widget.repeatedRoutePolylines!) {
          if (span.length >= 2) {
            polylines.add(
              Polyline(
                points: span,
                strokeWidth: 4.0,
                color: const Color(0xFF64748B).withValues(alpha: 0.78),
              ),
            );
          }
        }
      }
      // Newly discovered segments rendered in bright glowing discovery emerald/teal
      if (widget.newRoutePolylines != null) {
        for (final span in widget.newRoutePolylines!) {
          if (span.length >= 2) {
            polylines.add(
              Polyline(
                points: span,
                strokeWidth: 7.5,
                color: AppTheme.primary.withValues(alpha: 0.35),
              ),
            );
            polylines.add(
              Polyline(
                points: span,
                strokeWidth: 4.5,
                color: AppTheme.primary,
              ),
            );
          }
        }
      }
    } else if (widget.activePoints != null && widget.activePoints!.length >= 2) {
      final activeLatLngs = widget.activePoints!.map((p) => LatLng(p.latitude, p.longitude)).toList();
      // Outer glow polyline
      polylines.add(
        Polyline(
          points: activeLatLngs,
          strokeWidth: 7.0,
          color: AppTheme.primary.withOpacity(0.4),
        ),
      );
      // Main core line
      polylines.add(
        Polyline(
          points: activeLatLngs,
          strokeWidth: 4.0,
          color: AppTheme.primary,
        ),
      );
    }

    // Markers list
    final List<Marker> markers = [];

    // Start point marker
    if (widget.startPoint != null) {
      markers.add(
        Marker(
          point: widget.startPoint!,
          width: 38,
          height: 38,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: const Icon(Icons.flag_rounded, color: Colors.white, size: 22),
          ),
        ),
      );
    }

    // End point marker
    if (widget.endPoint != null) {
      markers.add(
        Marker(
          point: widget.endPoint!,
          width: 38,
          height: 38,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 24),
          ),
        ),
      );
    }

    // Waypoint / POI markers
    if (widget.waypoints != null) {
      for (final wp in widget.waypoints!) {
        final isPhoto = wp.hasPhoto;
        final hasValidFile = isPhoto && File(wp.photoPath!).existsSync();
        final markerColor = isPhoto ? const Color(0xFF8B5CF6) : Colors.orange;

        markers.add(
          Marker(
            point: LatLng(wp.latitude, wp.longitude),
            width: isPhoto ? 40 : 36,
            height: isPhoto ? 40 : 36,
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    title: Row(
                      children: [
                        Icon(isPhoto ? Icons.photo_camera_rounded : Icons.place, color: markerColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            wp.name,
                            style: const TextStyle(fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasValidFile) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(wp.photoPath!),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          wp.note ?? (isPhoto ? 'Ảnh chụp check-in khám phá' : 'Điểm mốc đã khám phá'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ExternalMapService().openGoogleMaps(
                              wp.latitude,
                              wp.longitude,
                              label: wp.name,
                            );
                          },
                          icon: const Icon(Icons.map_outlined, size: 16, color: Colors.blue),
                          label: const Text('Xem trên Google Maps', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blue),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size.fromHeight(36),
                          ),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ExternalMapService().openGooglePhotos(
                              lat: wp.latitude,
                              lng: wp.longitude,
                              timestamp: wp.timestamp,
                              placeName: wp.name,
                            );
                          },
                          icon: const Icon(Icons.photo_library_outlined, size: 16, color: Colors.teal),
                          label: const Text('Xem ảnh Google Photos', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.teal),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: const Size.fromHeight(36),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Icon(
                  isPhoto ? Icons.photo_camera_rounded : Icons.star_rounded,
                  color: Colors.white,
                  size: isPhoto ? 20 : 22,
                ),
              ),
            ),
          ),
        );
      }
    }

    // Highlighted scrubber marker for replay/inspection (shows vehicle icon at that point!)
    if (widget.highlightedPoint != null) {
      final replayVehicle = widget.highlightedVehicleType;
      markers.add(
        Marker(
          point: widget.highlightedPoint!,
          width: replayVehicle != null ? 36 : 24,
          height: replayVehicle != null ? 36 : 24,
          rotate: true,
          child: Container(
            decoration: BoxDecoration(
              color: replayVehicle != null ? settings.vehicleColor : Colors.amber,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
            ),
            child: replayVehicle != null
                ? Icon(replayVehicle.icon, color: Colors.white, size: 19)
                : null,
          ),
        ),
      );
    }

    // Home ("Nhà") + Custom Pinned Places (work, school, cafe, scenic...)
    final tripProvider = Provider.of<TripProvider>(context);
    final List<CircleMarker> circles = [];
    if (widget.showHomePin && settings.homeLatLng != null) {
      circles.add(
        CircleMarker(
          point: settings.homeLatLng!,
          radius: settings.homeRadiusMeters.toDouble(),
          useRadiusInMeter: true,
          color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
          borderColor: const Color(0xFFF59E0B).withValues(alpha: 0.6),
          borderStrokeWidth: 1.2,
        ),
      );
      markers.add(
        Marker(
          point: settings.homeLatLng!,
          width: 72,
          height: 62,
          alignment: Alignment.topCenter,
          rotate: true,
          child: GestureDetector(
            onTap: () => _showHomePinSheet(context, settings),
            child: const HomePinMarker(),
          ),
        ),
      );
    }

    if (widget.showHomePin && tripProvider.pinnedPlaces.isNotEmpty) {
      for (final place in tripProvider.pinnedPlaces) {
        final color = place.category.color;
        circles.add(
          CircleMarker(
            point: LatLng(place.latitude, place.longitude),
            radius: place.radiusMeters.toDouble(),
            useRadiusInMeter: true,
            color: color.withValues(alpha: 0.12),
            borderColor: color.withValues(alpha: 0.55),
            borderStrokeWidth: 1.1,
          ),
        );
        markers.add(
          Marker(
            point: LatLng(place.latitude, place.longitude),
            width: 100,
            height: 62,
            alignment: Alignment.topCenter,
            rotate: true,
            child: GestureDetector(
              onTap: () => _showPinnedPlaceSheet(context, place),
              child: PinnedPlaceMarker(place: place),
            ),
          ),
        );
      }
    }

    // Current live user location marker (blue dot + beam when idle, vehicle badge + beam when recording)
    if (widget.userLocation != null) {
      markers.add(
        Marker(
          point: widget.userLocation!,
          width: UserLocationMarker.size,
          height: UserLocationMarker.size,
          rotate: true,
          child: GestureDetector(
            onTap: () => VehiclePickerSheet.show(context),
            child: UserLocationMarker(
              vehicleMode: widget.isVehicleMode,
              vehicleType: settings.vehicleType,
              vehicleColor: settings.vehicleColor,
              fallbackHeading: widget.movementHeading,
            ),
          ),
        ),
      );
    }

    if (_lastStyle != settings.mapStyle) {
      _lastStyle = settings.mapStyle;
      _hasTileError = false;
    }

    syncVectorStyle(settings);
    final isVector = GoongService.isVectorStyle(settings.mapStyle);
    final showErrorBanner = (!isVector && _hasTileError) || (isVector && vectorError != null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableForVertical = constraints.maxHeight - widget.controlsBottomOffset - 16;
        final useHorizontalControls = availableForVertical < 260 ||
            (constraints.maxWidth > constraints.maxHeight && constraints.maxHeight < 340);

        final controlsList = <Widget>[
          if (_mapRotationDeg.abs() > 3.0)
            _mapActionButton(
              icon: Icons.explore_outlined,
              tooltip: 'Xoay về hướng Bắc',
              compact: useHorizontalControls,
              iconColor: Colors.redAccent,
              onPressed: _resetNorth,
            ),
          if (widget.showHomePin)
            _mapActionButton(
              icon: Icons.add_location_alt_outlined,
              tooltip: 'Ghim địa điểm (Nhà, Công ty, Quán quen...)',
              compact: useHorizontalControls,
              iconColor: const Color(0xFFD97706),
              onPressed: () {
                LatLng target;
                try {
                  target = widget.userLocation ?? _mapController.camera.center;
                } catch (_) {
                  target = fallbackCenter;
                }
                PinnedPlaceDialog.show(context, initialPoint: target);
              },
            ),
          _mapActionButton(
            icon: Icons.download_for_offline_outlined,
            tooltip: 'Tải sẵn bản đồ ngoại tuyến',
            compact: useHorizontalControls,
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => OfflineMapPreloadDialog(
                  currentLocation: widget.userLocation ?? widget.center,
                ),
              );
            },
          ),
          _mapActionButton(
            icon: Icons.layers_outlined,
            tooltip: 'Kiểu bản đồ',
            compact: useHorizontalControls,
            onPressed: () => _showStyleSelector(context),
          ),
          _mapActionButton(
            icon: Icons.my_location_rounded,
            tooltip: _isFollowingUser ? 'Đang theo dõi vị trí' : 'Vị trí của tôi',
            compact: useHorizontalControls,
            iconColor: _isFollowingUser ? AppTheme.primary : null,
            onPressed: _recenterOnUser,
          ),
          _mapActionButton(
            icon: Icons.add,
            tooltip: 'Thu phóng',
            compact: useHorizontalControls,
            onPressed: _zoomIn,
          ),
          _mapActionButton(
            icon: Icons.remove,
            tooltip: 'Thu nhỏ',
            compact: useHorizontalControls,
            onPressed: _zoomOut,
          ),
        ];

        final double requiredHeight = useHorizontalControls
            ? 54.0
            : (controlsList.length * 46.0 + 16.0).clamp(180.0, 340.0);
        final double maxAllowedBottom = constraints.maxHeight > (requiredHeight + 12)
            ? constraints.maxHeight - requiredHeight
            : 12.0;
        final double effectiveBottom = widget.controlsBottomOffset < 12.0
            ? 12.0
            : (widget.controlsBottomOffset > maxAllowedBottom
                ? maxAllowedBottom
                : widget.controlsBottomOffset);

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: fallbackCenter,
                initialZoom: widget.initialZoom,
                minZoom: 3.0,
                maxZoom: isVector ? 20.0 : 18.0,
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture && _isFollowingUser) {
                    setState(() => _isFollowingUser = false);
                  }
                  if ((_mapRotationDeg - camera.rotation).abs() > 1.5) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _mapRotationDeg = camera.rotation);
                      }
                    });
                  }
                },
                onLongPress: widget.showHomePin
                    ? (_, latLng) => PinnedPlaceDialog.show(context, initialPoint: latLng)
                    : null,
              ),
              children: [
                ...buildBaseMapLayers(
                  settings,
                  onRasterTileError: () {
                    if (!_hasTileError && mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_hasTileError) {
                          setState(() => _hasTileError = true);
                        }
                      });
                    }
                  },
                ),
                if (circles.isNotEmpty) CircleLayer(circles: circles),
                if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
              ],
            ),

            // Vector map attribution chip
            if (isVector && vectorStyle != null && vectorStyle!.attributions.isNotEmpty)
              Positioned(
                left: 12,
                bottom: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      vectorStyle!.attributions.map((a) => a.text).join(' · '),
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                    ),
                  ),
                ),
              ),

            // Vector style loading indicator
            if (isVector && isLoadingVectorStyle)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Đang tải bản đồ Vector NDAMaps...',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Non-intrusive warning banner when chosen tile/vector provider fails
            if (showErrorBanner)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber, width: 1.5),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _getStyleErrorMessage(settings.mapStyle),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _showStyleSelector(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Đổi bản đồ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating Map Controls (adaptive vertical stack or compact horizontal strip)
            if (widget.showControls)
              Positioned(
                right: 12,
                bottom: effectiveBottom,
                child: useHorizontalControls
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < controlsList.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            controlsList[i],
                          ],
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < controlsList.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            controlsList[i],
                          ],
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }

  Widget _mapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool compact = false,
    Color? iconColor,
  }) {
    final btnSize = compact ? 36.0 : 40.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor ?? const Color(0xFF1E293B), size: compact ? 18 : 20),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
