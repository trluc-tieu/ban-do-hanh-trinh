import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/map_settings_provider.dart';
import '../services/goong_service.dart';
import '../services/nearby_places_service.dart';
import '../theme/app_theme.dart';
import 'vector_map_style_mixin.dart';

/// Interactive mini-map showing named nearby POIs directly on the map and in a
/// quick-select strip for 1-tap check-in and 15-minute stay confirmation.
class PlacePickerMapWidget extends StatefulWidget {
  final LatLng center;
  final double mapHeight;
  final bool expandMap;
  final String? selectedPlaceId;
  final LatLng? selectedPoint;
  final ValueChanged<NearbyPlace> onPlaceSelected;
  final ValueChanged<LatLng>? onMapPointTapped;

  const PlacePickerMapWidget({
    super.key,
    required this.center,
    this.mapHeight = 200,
    this.expandMap = false,
    this.selectedPlaceId,
    this.selectedPoint,
    required this.onPlaceSelected,
    this.onMapPointTapped,
  });

  @override
  State<PlacePickerMapWidget> createState() => _PlacePickerMapWidgetState();
}

class _PlacePickerMapWidgetState extends State<PlacePickerMapWidget>
    with VectorMapStyleMixin<PlacePickerMapWidget> {
  final MapController _mapController = MapController();
  List<NearbyPlace> _places = [];
  bool _isLoadingPlaces = true;
  late LatLng _searchCenter;
  int _fetchEpoch = 0;

  @override
  void initState() {
    super.initState();
    _searchCenter = widget.center;
    _loadNearbyPlaces(_searchCenter);
  }

  Future<void> _loadNearbyPlaces(LatLng target) async {
    final epoch = ++_fetchEpoch;
    setState(() => _isLoadingPlaces = true);

    final places = await NearbyPlacesService().fetchNearbyPlaces(
      target.latitude,
      target.longitude,
      radiusMeters: 350,
    );

    if (!mounted || epoch != _fetchEpoch) return;
    setState(() {
      _places = places;
      _isLoadingPlaces = false;
    });
  }

  void _selectPlace(NearbyPlace place) {
    widget.onPlaceSelected(place);
    try {
      _mapController.move(
        LatLng(place.latitude, place.longitude),
        _mapController.camera.zoom.clamp(16.5, 19.0),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    syncVectorStyle(settings);
    final isVector = GoongService.isVectorStyle(settings.mapStyle);

    final mapWidget = Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.selectedPoint ?? widget.center,
            initialZoom: 17.0,
            minZoom: 12.0,
            maxZoom: isVector ? 20.0 : 18.0,
            onTap: (_, tappedPoint) {
              widget.onMapPointTapped?.call(tappedPoint);
            },
          ),
          children: [
            ...buildBaseMapLayers(settings, onRasterTileError: () {}),
            MarkerLayer(
              markers: _buildMarkers(),
            ),
          ],
        ),

        // Top-left status / instruction pill
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.84),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingPlaces) ...[
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Đang tìm địa điểm...',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ] else ...[
                  const Icon(Icons.touch_app_rounded, color: Colors.amberAccent, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    _places.isNotEmpty
                        ? 'Chạm tên quán/địa điểm (${_places.length})'
                        : 'Chạm bản đồ chọn vị trí',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Top-right compact zoom & refresh buttons
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Tìm địa điểm quanh tâm bản đồ',
                onTap: () {
                  final center = _mapController.camera.center;
                  _searchCenter = center;
                  _loadNearbyPlaces(center);
                },
              ),
              const SizedBox(width: 4),
              _miniButton(
                icon: Icons.add,
                tooltip: 'Phóng to',
                onTap: () => _mapController.move(
                  _mapController.camera.center,
                  (_mapController.camera.zoom + 1).clamp(12.0, 20.0),
                ),
              ),
              const SizedBox(width: 4),
              _miniButton(
                icon: Icons.remove,
                tooltip: 'Thu nhỏ',
                onTap: () => _mapController.move(
                  _mapController.camera.center,
                  (_mapController.camera.zoom - 1).clamp(12.0, 20.0),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final Widget framedMap = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(14),
        ),
        height: widget.expandMap ? null : widget.mapHeight,
        child: mapWidget,
      ),
    );

    return Column(
      mainAxisSize: widget.expandMap ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expandMap) Expanded(child: framedMap) else framedMap,
        const SizedBox(height: 8),
        _buildSuggestionStrip(),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];

    // Original user / stay point reference dot
    markers.add(
      Marker(
        point: widget.center,
        width: 28,
        height: 28,
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );

    // Clickable named POI pills directly on the map (show closest 12 to keep legible)
    final displayed = _places.take(12).toList();
    for (final place in displayed) {
      final isSelected = widget.selectedPlaceId == place.id;
      markers.add(
        Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 156,
          height: 44,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _selectPlace(place),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : Colors.white.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? Colors.white : AppTheme.primary,
                      width: isSelected ? 1.8 : 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isSelected ? 0.35 : 0.18),
                        blurRadius: isSelected ? 6 : 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.place,
                        size: 12,
                        color: isSelected ? Colors.white : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : Colors.orange.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Selected custom point pin (when tapped manually away from a POI)
    if (widget.selectedPoint != null && widget.selectedPlaceId == null) {
      markers.add(
        Marker(
          point: widget.selectedPoint!,
          width: 32,
          height: 32,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_pin,
            color: Colors.redAccent,
            size: 32,
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildSuggestionStrip() {
    if (_isLoadingPlaces && _places.isEmpty) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'Đang quét tên địa điểm quanh bạn...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_places.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Chưa tìm thấy tên quán/địa điểm gần đây. Chạm lên bản đồ để chọn toạ độ hoặc nhập tên bên dưới.',
          style: TextStyle(fontSize: 11.5, color: Colors.black54),
        ),
      );
    }

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _places.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final p = _places[idx];
          final isSelected = widget.selectedPlaceId == p.id;
          final subtitle = [
            p.formattedDistance,
            if (p.category != null) p.category!,
          ].join(' • ');

          return InkWell(
            onTap: () => _selectPlace(p),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 195),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary.withOpacity(0.14)
                    : Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : Colors.black12,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.primary : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 17, color: const Color(0xFF1E293B)),
          ),
        ),
      ),
    );
  }
}
