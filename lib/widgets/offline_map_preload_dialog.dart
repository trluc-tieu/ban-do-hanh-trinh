import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/offline_map_service.dart';
import '../theme/app_theme.dart';

class OfflineMapPreloadDialog extends StatefulWidget {
  final LatLng? currentLocation;

  const OfflineMapPreloadDialog({
    super.key,
    this.currentLocation,
  });

  @override
  State<OfflineMapPreloadDialog> createState() => _OfflineMapPreloadDialogState();
}

class _OfflineMapPreloadDialogState extends State<OfflineMapPreloadDialog> {
  // Mode: 0 = Current Location / Radius, 1 = By Province
  int _selectedMode = 0;
  double _radiusKm = 5.0;
  String _selectedProvince = 'Hà Nội';
  int _detailLevel = 1; // 0 = Standard (z12-14), 1 = High detail (z12-15)
  int _selectedSourceIndex = 0; // Source to download

  final List<({String name, String urlTemplate, String desc})> _sources = [
    (
      name: 'Google Maps Đường Phố (Khuyên dùng)',
      urlTemplate: 'https://mt1.google.com/vt/lyrs=m&hl=vi&gl=VN&x={x}&y={y}&z={z}',
      desc: 'Đường phố & địa danh tiếng Việt chi tiết nhất',
    ),
    (
      name: 'Google Maps Vệ Tinh Lai (Hybrid)',
      urlTemplate: 'https://mt1.google.com/vt/lyrs=y&hl=vi&gl=VN&x={x}&y={y}&z={z}',
      desc: 'Ảnh vệ tinh thực tế kết hợp tên đường tiếng Việt',
    ),
    (
      name: 'OpenStreetMap Tiếng Việt (HOT)',
      urlTemplate: 'https://tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      desc: 'Bản đồ cộng đồng HOT tiếng Việt sắc nét',
    ),
    (
      name: 'OpenStreetMap Tiêu Chuẩn',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      desc: 'Nguồn mở quốc tế chuẩn mực',
    ),
    (
      name: 'Ảnh Vệ Tinh Thực Tế (ESRI Satellite)',
      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      desc: 'Ảnh vệ tinh chụp từ quỹ đạo chi tiết',
    ),
  ];

  int _cachedTileCount = 0;
  int _cachedSizeBytes = 0;
  bool _isLoadingStats = true;

  bool _isDownloading = false;
  OfflineDownloadProgress? _currentProgress;
  StreamSubscription<OfflineDownloadProgress>? _sub;

  // Key Vietnam provincial coordinates
  final Map<String, LatLng> _provinceCoords = {
    'Hà Nội': const LatLng(21.028511, 105.854444),
    'TP. Hồ Chí Minh': const LatLng(10.823099, 106.629664),
    'Đà Nẵng': const LatLng(16.054407, 108.202167),
    'Hải Phòng': const LatLng(20.844912, 106.688084),
    'Cần Thơ': const LatLng(10.045162, 105.746857),
    'Quảng Ninh': const LatLng(20.9505, 107.0734),
    'Lâm Đồng': const LatLng(11.9404, 108.4583),
    'Khánh Hoà': const LatLng(12.2388, 109.1967),
    'Ninh Bình': const LatLng(20.2506, 105.9745),
    'Thừa Thiên Huế': const LatLng(16.4637, 107.5909),
    'Bà Rịa - Vũng Tàu': const LatLng(10.3460, 107.0843),
    'Lào Cai': const LatLng(22.4856, 103.9707),
    'Hà Giang': const LatLng(22.8233, 104.9836),
    'Kiên Giang': const LatLng(10.0125, 105.0809),
  };

  @override
  void initState() {
    super.initState();
    _loadStorageStats();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadStorageStats() async {
    setState(() => _isLoadingStats = true);
    final stats = await OfflineMapService().getOfflineStats();
    if (mounted) {
      setState(() {
        _cachedTileCount = stats.count;
        _cachedSizeBytes = stats.totalBytes;
        _isLoadingStats = false;
      });
    }
  }

  LatLng _getActiveCenter() {
    if (_selectedMode == 0) {
      return widget.currentLocation ?? const LatLng(21.028511, 105.854444);
    } else {
      return _provinceCoords[_selectedProvince] ?? const LatLng(21.028511, 105.854444);
    }
  }

  List<TileCoord> _computeTilesToDownload() {
    final center = _getActiveCenter();
    final minZ = 12;
    final maxZ = _detailLevel == 0 ? 14 : 15;

    return OfflineMapService().calculateTilesForRadius(
      centerLat: center.latitude,
      centerLng: center.longitude,
      radiusKm: _radiusKm,
      minZoom: minZ,
      maxZoom: maxZ,
    );
  }

  void _startDownload() {
    final tiles = _computeTilesToDownload();
    if (tiles.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _currentProgress = OfflineDownloadProgress(
        total: tiles.length,
        completed: 0,
        failed: 0,
        currentTileInfo: 'Bắt đầu kết nối tải bản đồ...',
      );
    });

    _sub?.cancel();
    final selectedSource = _sources[_selectedSourceIndex];
    _sub = OfflineMapService().downloadTiles(
      tiles: tiles,
      tileUrlTemplate: selectedSource.urlTemplate,
    ).listen(
      (progress) {
        if (mounted) {
          setState(() {
            _currentProgress = progress;
            if (progress.isFinished) {
              _isDownloading = false;
              _loadStorageStats();
            }
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isDownloading = false);
        }
      },
    );
  }

  void _cancelDownload() {
    OfflineMapService().cancelDownload();
    _sub?.cancel();
    setState(() => _isDownloading = false);
  }

  Future<void> _clearAllOfflineTiles() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa bản đồ tải sẵn?'),
        content: const Text('Thao tác này sẽ giải phóng toàn bộ các ô bản đồ ngoại tuyến đã tải về máy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Xóa toàn bộ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await OfflineMapService().clearOfflineTiles();
      await _loadStorageStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã dọn dẹp sạch toàn bộ bản đồ ngoại tuyến.')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final calculatedTiles = _computeTilesToDownload();
    final estimatedMb = (calculatedTiles.length * 28) / 1024.0; // ~28KB per tile average

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.download_for_offline_rounded, color: AppTheme.primary, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tải Sẵn Bản Đồ Ngoại Tuyến',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lưu bản đồ vào máy để xem và thu phóng mượt mà ngay cả khi mất sóng, đi rừng núi hoặc không có 4G/Wifi.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 14),

            // Mode Selection
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: _modeButton(0, 'Khu vực hiện tại', Icons.my_location),
                  ),
                  Expanded(
                    child: _modeButton(1, 'Theo Tỉnh/Thành', Icons.location_city),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (_selectedMode == 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Bán kính khu vực:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${_radiusKm.toInt()} km', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ],
              ),
              Slider(
                value: _radiusKm,
                min: 2.0,
                max: 20.0,
                divisions: 9,
                label: '${_radiusKm.toInt()} km',
                onChanged: _isDownloading
                    ? null
                    : (val) {
                        setState(() => _radiusKm = val);
                      },
              ),
            ] else ...[
              const Text('Chọn Tỉnh / Thành phố:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedProvince,
                isDense: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _provinceCoords.keys.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)));
                }).toList(),
                onChanged: _isDownloading
                    ? null
                    : (val) {
                        if (val != null) setState(() => _selectedProvince = val);
                      },
              ),
            ],

            const SizedBox(height: 12),
            const Text('Mức độ chi tiết:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Cơ bản (z12-14)', style: TextStyle(fontSize: 12)),
                    selected: _detailLevel == 0,
                    onSelected: _isDownloading ? null : (s) => setState(() => _detailLevel = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Chi tiết (z12-15)', style: TextStyle(fontSize: 12)),
                    selected: _detailLevel == 1,
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                    onSelected: _isDownloading ? null : (s) => setState(() => _detailLevel = 1),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Text('Nguồn bản đồ tải về:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _selectedSourceIndex,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: List.generate(_sources.length, (idx) {
                return DropdownMenuItem(
                  value: idx,
                  child: Text(
                    _sources[idx].name,
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
              onChanged: _isDownloading
                  ? null
                  : (val) {
                      if (val != null) setState(() => _selectedSourceIndex = val);
                    },
            ),
            const SizedBox(height: 4),
            Text(
              'Máy chủ: ${_sources[_selectedSourceIndex].urlTemplate}',
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),

            const SizedBox(height: 14),
            // Estimation badge
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ước tính: ${calculatedTiles.length} ô bản đồ (~${estimatedMb.toStringAsFixed(1)} MB)',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),

            // Progress bar if downloading
            if (_isDownloading && _currentProgress != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: _currentProgress!.percent,
                backgroundColor: Colors.grey.withOpacity(0.2),
                color: AppTheme.primary,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đã tải: ${_currentProgress!.completed}/${_currentProgress!.total} ô',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${(_currentProgress!.percent * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ],
              ),
              if (_currentProgress!.currentTileInfo != null) ...[
                const SizedBox(height: 2),
                Text(
                  _currentProgress!.currentTileInfo!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],

            if (!_isDownloading && _currentProgress != null && _currentProgress!.isFinished) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Đã hoàn tất tải ${_currentProgress!.completed} ô bản đồ!',
                        style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 24),

            // Storage status & Cleanup
            Row(
              children: [
                const Icon(Icons.sd_storage_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: _isLoadingStats
                      ? const Text('Đang kiểm tra...', style: TextStyle(fontSize: 12, color: Colors.grey))
                      : Text(
                          'Đang lưu: $_cachedTileCount ô (${_formatBytes(_cachedSizeBytes)})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                ),
                if (_cachedTileCount > 0 && !_isDownloading)
                  TextButton.icon(
                    onPressed: _clearAllOfflineTiles,
                    icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                    label: const Text('Dọn dẹp', style: TextStyle(fontSize: 11.5, color: Colors.redAccent)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (_isDownloading)
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('Dừng tải', style: TextStyle(color: Colors.redAccent)),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Bắt đầu tải'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ],
    );
  }

  Widget _modeButton(int mode, String title, IconData icon) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: _isDownloading ? null : () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isSelected ? AppTheme.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppTheme.primary : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
