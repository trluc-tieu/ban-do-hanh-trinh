import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/pinned_place.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/trip_provider.dart';
import '../services/goong_service.dart';
import '../services/place_search_service.dart';
import '../theme/app_theme.dart';
import 'user_location_marker.dart';
import 'vector_map_style_mixin.dart';

/// Interactive dialog to search, preview, and pin or edit any location on the map
/// ("Nhà", "Công ty", "Trường học", "Quán quen / Café", "Quán ăn", "Tham quan", "Bãi xe", "Yêu thích"),
/// even when the user is not physically at that location.
class PinnedPlaceDialog extends StatefulWidget {
  final LatLng initialPoint;
  final PinnedPlace? existingPlace;
  final bool allowHomeChoice;
  final bool showMapPreview;

  const PinnedPlaceDialog({
    super.key,
    required this.initialPoint,
    this.existingPlace,
    this.allowHomeChoice = true,
    this.showMapPreview = true,
  });

  static Future<void> show(
    BuildContext context, {
    LatLng? initialPoint,
    PinnedPlace? existingPlace,
    bool allowHomeChoice = true,
    bool showMapPreview = true,
  }) async {
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final start = existingPlace != null
        ? LatLng(existingPlace.latitude, existingPlace.longitude)
        : (initialPoint ??
            (tracking.currentPosition != null
                ? LatLng(tracking.currentPosition!.latitude, tracking.currentPosition!.longitude)
                : const LatLng(21.028511, 105.854444)));

    await showDialog<void>(
      context: context,
      builder: (_) => PinnedPlaceDialog(
        initialPoint: start,
        existingPlace: existingPlace,
        allowHomeChoice: allowHomeChoice && existingPlace == null,
        showMapPreview: showMapPreview,
      ),
    );
  }

  @override
  State<PinnedPlaceDialog> createState() => _PinnedPlaceDialogState();
}

class _PinnedPlaceDialogState extends State<PinnedPlaceDialog>
    with VectorMapStyleMixin<PinnedPlaceDialog> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  late LatLng _picked;
  late bool _isHomeSelected;
  late PinnedPlaceCategory _category;
  late int _radius;
  late TextEditingController _nameController;
  late TextEditingController _noteController;

  Timer? _debounce;
  int _searchEpoch = 0;
  bool _isSearching = false;
  bool _hasSearchedOnce = false;
  List<PlaceSearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPoint;
    _isHomeSelected = false;
    _category = widget.existingPlace?.category ?? PinnedPlaceCategory.work;
    _radius = widget.existingPlace?.radiusMeters ?? 50;
    _nameController = TextEditingController(
      text: widget.existingPlace?.name ?? _category.defaultName,
    );
    _noteController = TextEditingController(text: widget.existingPlace?.note ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    _noteController.dispose();
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
    setState(() {
      _isSearching = true;
    });

    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final pos = tracking.currentPosition;
    final results = await PlaceSearchService().searchPlaces(
      query,
      biasLat: pos?.latitude,
      biasLng: pos?.longitude,
      limit: 8,
    );

    if (!mounted || epoch != _searchEpoch) return;
    setState(() {
      _isSearching = false;
      _hasSearchedOnce = true;
      _searchResults = results;
    });
  }

  void _applySearchResult(PlaceSearchResult result) {
    FocusScope.of(context).unfocus();
    final target = LatLng(result.latitude, result.longitude);
    final inferred = result.suggestedCategory;

    setState(() {
      _picked = target;
      _searchResults = [];
      _hasSearchedOnce = false;
      if (!_isHomeSelected) {
        if (inferred != null && widget.existingPlace == null) {
          _category = inferred;
        }
        _nameController.text = result.name;
        if (_noteController.text.trim().isEmpty && result.address != result.name) {
          _noteController.text = result.address;
        }
      }
    });

    if (widget.showMapPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(target, 17.0);
        } catch (_) {}
      });
    }
  }

  Future<void> _saveCurrentOrDirect({PlaceSearchResult? directResult}) async {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    final lat = directResult?.latitude ?? _picked.latitude;
    final lng = directResult?.longitude ?? _picked.longitude;

    if (_isHomeSelected) {
      await settings.setHome(lat, lng);
      await settings.setHomeRadius(_radius);
      tracking.setHomeConfig(
        lat: lat,
        lng: lng,
        radiusMeters: _radius,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              directResult != null
                  ? 'Đã ghim "${directResult.name}" làm vị trí Nhà!'
                  : 'Đã ghim vị trí "Nhà" trên bản đồ!',
            ),
          ),
        );
      }
      return;
    }

    final chosenCat = (directResult?.suggestedCategory != null && widget.existingPlace == null)
        ? directResult!.suggestedCategory!
        : _category;

    final name = directResult != null
        ? directResult.name
        : (_nameController.text.trim().isEmpty
            ? chosenCat.defaultName
            : _nameController.text.trim());

    final note = directResult != null
        ? (directResult.address != directResult.name ? directResult.address : null)
        : (_noteController.text.trim().isEmpty ? null : _noteController.text.trim());

    if (widget.existingPlace != null) {
      final updated = widget.existingPlace!.copyWith(
        name: name,
        category: chosenCat,
        latitude: lat,
        longitude: lng,
        radiusMeters: _radius,
        note: note,
      );
      await tripProvider.updatePinnedPlace(updated);
    } else {
      final place = PinnedPlace(
        id: const Uuid().v4(),
        name: name,
        category: chosenCat,
        latitude: lat,
        longitude: lng,
        radiusMeters: _radius,
        note: note,
        createdAt: DateTime.now(),
      );
      await tripProvider.addPinnedPlace(place);
    }
    tracking.setPinnedPlaces(tripProvider.pinnedPlaces);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã ghim địa điểm "$name"!')),
      );
    }
  }

  void _selectCategory(PinnedPlaceCategory cat) {
    final prevDefault = _isHomeSelected ? 'Nhà' : _category.defaultName;
    setState(() {
      _isHomeSelected = false;
      _category = cat;
      if (_nameController.text.trim().isEmpty || _nameController.text.trim() == prevDefault) {
        _nameController.text = cat.defaultName;
      }
    });
  }

  void _selectHome() {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    setState(() {
      _isHomeSelected = true;
      _radius = settings.homeRadiusMeters;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    final tracking = Provider.of<TrackingProvider>(context, listen: false);

    if (widget.showMapPreview) {
      syncVectorStyle(settings);
    }
    final isVector = GoongService.isVectorStyle(settings.mapStyle);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height && size.height < 540;

    final activeColor = _isHomeSelected ? const Color(0xFFF59E0B) : _category.color;
    final activeIcon = _isHomeSelected ? Icons.home_rounded : _category.icon;
    final previewName = _isHomeSelected
        ? 'Nhà'
        : (_nameController.text.trim().isEmpty ? _category.defaultName : _nameController.text.trim());

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isLandscape ? 720 : 490,
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
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: activeColor.withValues(alpha: 0.16),
                    child: Icon(activeIcon, color: activeColor, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.existingPlace != null
                          ? 'Chỉnh sửa địa điểm ghim'
                          : 'Tìm & Ghim địa điểm trên bản đồ',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              const SizedBox(height: 10),

              // Search place by name / address / coordinates (even when far away!)
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchQueryChanged,
                onSubmitted: _performSearch,
                decoration: InputDecoration(
                  hintText: 'Nhập tên địa điểm, địa chỉ cần tìm để ghim...',
                  hintStyle: const TextStyle(fontSize: 12.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 20),
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
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 19, color: AppTheme.primary),
                                  tooltip: 'Tìm kiếm',
                                  onPressed: () => _performSearch(_searchController.text),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  tooltip: 'Xoá',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchResults = [];
                                      _hasSearchedOnce = false;
                                    });
                                  },
                                ),
                              ],
                            )
                          : null),
                  filled: true,
                  fillColor: AppTheme.primary.withValues(alpha: 0.06),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                ),
              ),

              // Live Search Results Dropdown Card
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 195),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final r = _searchResults[idx];
                      final inferred = r.suggestedCategory;
                      final icon = _isHomeSelected
                          ? Icons.home_rounded
                          : (inferred?.icon ?? Icons.place_rounded);
                      final color = _isHomeSelected
                          ? const Color(0xFFF59E0B)
                          : (inferred?.color ?? AppTheme.primary);

                      return InkWell(
                        onTap: () => _applySearchResult(r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: color.withValues(alpha: 0.14),
                                child: Icon(icon, size: 16, color: color),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      [
                                        if (r.formattedDistance != null) 'Cách ${r.formattedDistance}',
                                        r.address,
                                      ].join(' • '),
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
                                  backgroundColor: color.withValues(alpha: 0.16),
                                  foregroundColor: color,
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _saveCurrentOrDirect(directResult: r),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Không tìm thấy kết quả khớp tên này. Thử nhập kèm tên đường / quận / tỉnh hoặc chấm trực tiếp lên bản đồ.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Category icon selector
              const Text(
                'Chọn loại địa điểm & biểu tượng:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (widget.allowHomeChoice)
                    ChoiceChip(
                      avatar: Icon(
                        Icons.home_rounded,
                        size: 16,
                        color: _isHomeSelected ? Colors.white : const Color(0xFFF59E0B),
                      ),
                      label: const Text('Nhà', style: TextStyle(fontSize: 11.5)),
                      selected: _isHomeSelected,
                      selectedColor: const Color(0xFFF59E0B),
                      labelStyle: TextStyle(
                        color: _isHomeSelected ? Colors.white : null,
                        fontWeight: _isHomeSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _selectHome(),
                    ),
                  for (final cat in PinnedPlaceCategory.values)
                    ChoiceChip(
                      avatar: Icon(
                        cat.icon,
                        size: 16,
                        color: (!_isHomeSelected && _category == cat) ? Colors.white : cat.color,
                      ),
                      label: Text(cat.defaultName, style: const TextStyle(fontSize: 11.5)),
                      selected: !_isHomeSelected && _category == cat,
                      selectedColor: cat.color,
                      labelStyle: TextStyle(
                        color: (!_isHomeSelected && _category == cat) ? Colors.white : null,
                        fontWeight: (!_isHomeSelected && _category == cat)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _selectCategory(cat),
                    ),
                ],
              ),

              if (!_isHomeSelected) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Tên hiển thị trên bản đồ',
                    prefixIcon: Icon(activeIcon, color: activeColor, size: 19),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ / Ghi chú (tuỳ chọn)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],

              if (widget.showMapPreview) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: isLandscape ? 155 : 195,
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
                                  color: activeColor.withValues(alpha: 0.16),
                                  borderColor: activeColor,
                                  borderStrokeWidth: 1.5,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _picked,
                                  width: 100,
                                  height: 62,
                                  alignment: Alignment.topCenter,
                                  child: _isHomeSelected
                                      ? const HomePinMarker()
                                      : PinnedPlaceMarker(
                                          place: PinnedPlace(
                                            id: 'preview',
                                            name: previewName,
                                            category: _category,
                                            latitude: _picked.latitude,
                                            longitude: _picked.longitude,
                                            radiusMeters: _radius,
                                            createdAt: DateTime.now(),
                                          ),
                                        ),
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
                const SizedBox(height: 4),
                Text(
                  'Chạm bản đồ để tinh chỉnh • ${_picked.latitude.toStringAsFixed(5)}, ${_picked.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],

              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Bán kính nhận diện:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  for (final r in [20, 30, 50, 100, 150])
                    ChoiceChip(
                      label: Text('${r}m', style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      selected: _radius == r,
                      selectedColor: activeColor.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _radius = r),
                    ),
                ],
              ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Huỷ'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: activeColor),
                    icon: Icon(activeIcon, size: 18),
                    label: Text(_isHomeSelected
                        ? 'Lưu vị trí Nhà'
                        : (widget.existingPlace != null ? 'Cập nhật' : 'Lưu ghim')),
                    onPressed: () => _saveCurrentOrDirect(),
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
