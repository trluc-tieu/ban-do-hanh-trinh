import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../services/goong_service.dart';
import '../services/place_search_service.dart';
import '../theme/app_theme.dart';
import 'user_location_marker.dart';
import 'vector_map_style_mixin.dart';

/// Interactive map dialog for searching and pinning the user's "Nhà" location
/// (even when the user is not currently at home) and its detection radius.
class HomePickerDialog extends StatefulWidget {
  final LatLng initialPoint;

  const HomePickerDialog({super.key, required this.initialPoint});

  static Future<void> show(BuildContext context) async {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);

    final start = settings.homeLatLng ??
        (tracking.currentPosition != null
            ? LatLng(tracking.currentPosition!.latitude, tracking.currentPosition!.longitude)
            : const LatLng(21.028511, 105.854444));

    await showDialog<void>(
      context: context,
      builder: (_) => HomePickerDialog(initialPoint: start),
    );
  }

  @override
  State<HomePickerDialog> createState() => _HomePickerDialogState();
}

class _HomePickerDialogState extends State<HomePickerDialog>
    with VectorMapStyleMixin<HomePickerDialog> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  late LatLng _picked;
  late int _radius;

  Timer? _debounce;
  int _searchEpoch = 0;
  bool _isSearching = false;
  bool _hasSearchedOnce = false;
  List<PlaceSearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPoint;
    _radius = Provider.of<MapSettingsProvider>(context, listen: false).homeRadiusMeters;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _isSearching = false;
        _hasSearchedOnce = false;
        _searchResults = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final epoch = ++_searchEpoch;
    setState(() => _isSearching = true);

    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final pos = tracking.currentPosition;
    final results = await PlaceSearchService().searchPlaces(
      query,
      biasLat: pos?.latitude,
      biasLng: pos?.longitude,
      limit: 6,
    );

    if (!mounted || epoch != _searchEpoch) return;
    setState(() {
      _isSearching = false;
      _hasSearchedOnce = true;
      _searchResults = results;
    });
  }

  void _selectResult(PlaceSearchResult r) {
    FocusScope.of(context).unfocus();
    final pt = LatLng(r.latitude, r.longitude);
    setState(() {
      _picked = pt;
      _searchResults = [];
      _hasSearchedOnce = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(pt, 17.0);
      } catch (_) {}
    });
  }

  Future<void> _saveHome({LatLng? overridePoint}) async {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final pt = overridePoint ?? _picked;

    await settings.setHome(pt.latitude, pt.longitude);
    await settings.setHomeRadius(_radius);
    tracking.setHomeConfig(
      lat: pt.latitude,
      lng: pt.longitude,
      radiusMeters: _radius,
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã ghim vị trí "Nhà" thành công!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    syncVectorStyle(settings);
    final isVector = GoongService.isVectorStyle(settings.mapStyle);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height && size.height < 540;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isLandscape ? 700 : 470,
          maxHeight: size.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.home_rounded, color: Color(0xFFF59E0B), size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tìm & Ghim vị trí "Nhà"',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Search address / apartment / street for Home
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchQueryChanged,
                onSubmitted: _performSearch,
                decoration: InputDecoration(
                  hintText: 'Nhập địa chỉ, chung cư, đường, phường của Nhà...',
                  hintStyle: const TextStyle(fontSize: 12.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFD97706), size: 20),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                  _hasSearchedOnce = false;
                                });
                              },
                            )
                          : null),
                  filled: true,
                  fillColor: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                ),
              ),

              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 175),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final r = _searchResults[idx];
                      return InkWell(
                        onTap: () => _selectResult(r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: Row(
                            children: [
                              const Icon(Icons.home_work_outlined, size: 18, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      r.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  foregroundColor: const Color(0xFFB45309),
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _saveHome(overridePoint: LatLng(r.latitude, r.longitude)),
                                child: const Text(
                                  'Ghim ngay',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else if (_hasSearchedOnce && !_isSearching) ...[
                const SizedBox(height: 6),
                const Text(
                  'Không tìm thấy địa chỉ khớp. Thử gõ kèm tên quận/huyện/tỉnh hoặc chọn trực tiếp trên bản đồ.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
                ),
              ],

              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: isLandscape ? 170 : 215,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _picked,
                          initialZoom: 16.5,
                          minZoom: 5.0,
                          maxZoom: isVector ? 20.0 : 18.0,
                          onTap: (_, latLng) => setState(() => _picked = latLng),
                        ),
                        children: [
                          ...buildBaseMapLayers(settings, onRasterTileError: () {}),
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: _picked,
                                radius: _radius.toDouble(),
                                useRadiusInMeter: true,
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                                borderColor: const Color(0xFFF59E0B),
                                borderStrokeWidth: 1.5,
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _picked,
                                width: 70,
                                height: 60,
                                alignment: Alignment.topCenter,
                                child: const HomePinMarker(),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(10),
                          elevation: 2,
                          child: IconButton(
                            icon: const Icon(Icons.my_location_rounded, size: 19, color: AppTheme.primary),
                            tooltip: 'Lấy vị trí hiện tại',
                            onPressed: () {
                              final pos = tracking.currentPosition;
                              if (pos != null) {
                                final pt = LatLng(pos.latitude, pos.longitude);
                                setState(() => _picked = pt);
                                _mapController.move(pt, 16.5);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Bán kính nhận diện:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  for (final r in [20, 30, 50, 100, 150])
                    ChoiceChip(
                      label: Text('${r}m', style: const TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      selected: _radius == r,
                      selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _radius = r),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Huỷ'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('Lưu vị trí Nhà'),
                    onPressed: () => _saveHome(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
