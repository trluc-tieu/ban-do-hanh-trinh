import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/province_stats.dart';
import '../models/waypoint.dart';
import '../providers/trip_provider.dart';
import '../services/companion_quotes.dart';
import '../services/external_map_service.dart';
import '../services/photo_discovery_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class PhotoDiscoveryScreen extends StatefulWidget {
  const PhotoDiscoveryScreen({super.key});

  @override
  State<PhotoDiscoveryScreen> createState() => _PhotoDiscoveryScreenState();
}

class _PhotoDiscoveryScreenState extends State<PhotoDiscoveryScreen> {
  final PhotoDiscoveryService _photoService = PhotoDiscoveryService();
  bool _isProcessing = false;
  String _statusMessage = '';
  String _selectedProvinceFilter = 'Tất cả';

  Future<void> _handlePickOriginalFiles() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Đang trích xuất toạ độ GPS từ file ảnh gốc...';
    });

    try {
      final result = await _photoService.pickOriginalPhotoFiles();
      if (mounted) {
        final tripProvider = Provider.of<TripProvider>(context, listen: false);
        await tripProvider.refreshAll();

        String msg;
        if (result.totalSelected == 0) {
          msg = 'Chưa chọn file ảnh nào.';
        } else if (result.geotaggedFound == 0) {
          msg =
              'Đã chọn ${result.totalSelected} file ảnh, nhưng không tìm thấy toạ độ GPS trong thẻ EXIF.\n(Mẹo: Đảm bảo máy ảnh đã bật "Lưu vị trí" khi chụp).';
        } else {
          msg =
              'Thành công! Đã thêm ${result.geotaggedFound} điểm ảnh từ ${result.totalSelected} ảnh gốc.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor:
                result.geotaggedFound > 0 ? AppTheme.primary : Colors.blueGrey,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi đọc file ảnh: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _handlePickPhotos() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Đang đọc toạ độ GPS từ ảnh...';
    });

    try {
      final result = await _photoService.pickAndImportPhotos();
      if (mounted) {
        final tripProvider = Provider.of<TripProvider>(context, listen: false);
        await tripProvider.refreshAll();

        String msg;
        if (result.totalSelected == 0) {
          msg = 'Chưa chọn ảnh nào.';
        } else if (result.geotaggedFound == 0) {
          msg =
              'Đã chọn ${result.totalSelected} ảnh, nhưng không tìm thấy toạ độ GPS (EXIF) trong các ảnh này.';
        } else {
          msg =
              'Thành công! Đã thêm ${result.geotaggedFound} ảnh khám phá từ ${result.totalSelected} ảnh đã chọn.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor:
                result.geotaggedFound > 0 ? AppTheme.primary : Colors.blueGrey,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi đọc ảnh: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _handleScanDevicePhotos() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Đang quét thư viện ảnh máy tìm toạ độ GPS...';
    });

    try {
      final result = await _photoService.scanDeviceCameraPhotos();
      if (mounted) {
        final tripProvider = Provider.of<TripProvider>(context, listen: false);
        await tripProvider.refreshAll();

        String msg;
        if (result.totalSelected == 0) {
          msg =
              'Không tìm thấy ảnh chụp máy trong thư mục DCIM/Camera hoặc chưa cấp quyền.';
        } else if (result.geotaggedFound == 0) {
          msg =
              'Đã quét ${result.totalSelected} ảnh trên máy: không có dữ liệu GPS mới.';
        } else {
          msg =
              'Tuyệt vời! Đã tự động thêm ${result.geotaggedFound} ảnh khám phá từ máy.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor:
                result.geotaggedFound > 0 ? Colors.green : Colors.blueGrey,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi quét ảnh: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  List<Waypoint> _filterWaypoints(List<Waypoint> allPhotos) {
    if (_selectedProvinceFilter == 'Tất cả') {
      return allPhotos;
    }
    return allPhotos.where((wp) {
      final province = VietnamProvinces.matchProvince(
        wp.latitude,
        wp.longitude,
        '${wp.name} ${wp.note ?? ''}',
      );
      return province == _selectedProvinceFilter;
    }).toList();
  }

  Set<String> _extractProvinces(List<Waypoint> photos) {
    final set = <String>{'Tất cả'};
    for (final wp in photos) {
      final p = VietnamProvinces.matchProvince(
        wp.latitude,
        wp.longitude,
        '${wp.name} ${wp.note ?? ''}',
      );
      set.add(p);
    }
    return set;
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);
    final allPhotos = tripProvider.photoWaypoints;
    final filteredPhotos = _filterWaypoints(allPhotos);
    final availableProvinces = _extractProvinces(allPhotos);
    final folders = PhotoDiscoveryService.groupPhotosIntoFolders(filteredPhotos);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bộ Sưu Tập Ảnh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, color: Colors.teal),
            tooltip: 'Mở Google Photos',
            onPressed: () => ExternalMapService().openGooglePhotos(),
          ),
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
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeaderActionCard(
                  totalCount: allPhotos.length,
                  folderCount: folders.length,
                  provinceCount:
                      availableProvinces.length > 1 ? availableProvinces.length - 1 : 0,
                ),
              ),
              if (availableProvinces.length > 2)
                SliverToBoxAdapter(
                  child: _buildProvinceFilterBar(availableProvinces),
                ),
              if (folders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_copy_rounded,
                          size: 17,
                          color: Color(0xFF8B5CF6),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${folders.length} thư mục địa điểm • ${filteredPhotos.length} ảnh',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        const Text(
                          'Gộp theo tên & toạ độ gần nhau',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      final crossAxisCount = width >= 720
                          ? 4
                          : width >= 500
                              ? 3
                              : 2;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.80,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, index) {
                            final folder = folders[index];
                            return _buildFolderCard(folder);
                          },
                          childCount: folders.length,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionCard({
    required int totalCount,
    required int folderCount,
    required int provinceCount,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.folder_special_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thư mục ảnh theo địa điểm',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '$totalCount ảnh trong $folderCount thư mục • $provinceCount tỉnh/thành',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              CompanionQuotes.pickPhotoQuote(
                totalPhotos: totalCount,
                provinceCount: provinceCount,
              ),
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF475569),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _handlePickOriginalFiles,
                  icon: const Icon(Icons.file_present_rounded, size: 15),
                  label: const Text(
                    'File gốc (EXIF)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _handleScanDevicePhotos,
                  icon: const Icon(Icons.document_scanner_rounded,
                      size: 15, color: Colors.teal),
                  label: const Text(
                    'Quét DCIM',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.teal),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _handlePickPhotos,
                  icon: const Icon(Icons.photo_library_outlined,
                      size: 15, color: AppTheme.primary),
                  label: const Text(
                    'Google Photos',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProvinceFilterBar(Set<String> provinces) {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: provinces.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final p = provinces.elementAt(idx);
          final isSelected = p == _selectedProvinceFilter;
          return ChoiceChip(
            label: Text(
              p,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
            onSelected: (_) {
              setState(() => _selectedProvinceFilter = p);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text(
              'Chưa có thư mục ảnh nào',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thêm ảnh từ "File gốc (EXIF)", "Quét DCIM" hoặc "Google Photos". Các ảnh cùng tên địa điểm hoặc chụp gần toạ độ nhau sẽ tự động gom chung vào 1 thư mục!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCard(PhotoFolderCluster folder) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showFolderContentsSheet(folder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildFolderCoverPreview(folder.photos),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.folder_rounded,
                        color: Color(0xFFFBBF24),
                        size: 16,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${folder.count} ảnh',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 12,
                        color: Color(0xFF8B5CF6),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          folder.province,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd/MM/yyyy').format(folder.latestTimestamp),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCoverPreview(List<Waypoint> photos) {
    if (photos.length >= 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildPhotoThumb(photos[0])),
                const SizedBox(width: 1.5),
                Expanded(child: _buildPhotoThumb(photos[1])),
              ],
            ),
          ),
          const SizedBox(height: 1.5),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildPhotoThumb(photos[2])),
                const SizedBox(width: 1.5),
                Expanded(child: _buildPhotoThumb(photos[3])),
              ],
            ),
          ),
        ],
      );
    }
    if (photos.length >= 2) {
      return Row(
        children: [
          Expanded(flex: 3, child: _buildPhotoThumb(photos[0])),
          const SizedBox(width: 1.5),
          Expanded(flex: 2, child: _buildPhotoThumb(photos[1])),
        ],
      );
    }
    return _buildPhotoThumb(photos.first);
  }

  Widget _buildPhotoThumb(Waypoint wp) {
    final file = wp.photoPath != null ? File(wp.photoPath!) : null;
    final exists = file != null && file.existsSync();
    if (exists) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Icon(Icons.photo_outlined, color: Colors.grey, size: 28),
      ),
    );
  }

  void _showFolderContentsSheet(PhotoFolderCluster initialFolder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (ctx, scrollController) {
          // Re-read live photos from TripProvider so deletions reflect immediately
          final tripProvider = Provider.of<TripProvider>(ctx);
          final liveIds = initialFolder.photos.map((p) => p.id).toSet();
          final livePhotos = tripProvider.photoWaypoints
              .where((wp) => liveIds.contains(wp.id))
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

          if (livePhotos.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.canPop(sheetCtx)) Navigator.pop(sheetCtx);
            });
            return const SizedBox.shrink();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.folder_open_rounded,
                        color: Color(0xFF8B5CF6),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            initialFolder.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${initialFolder.province} • ${livePhotos.length} ảnh (${initialFolder.centerLat.toStringAsFixed(4)}, ${initialFolder.centerLng.toStringAsFixed(4)})',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.map_outlined, color: Colors.blue),
                      tooltip: 'Mở vị trí thư mục trên Google Maps',
                      onPressed: () {
                        ExternalMapService().openGoogleMaps(
                          initialFolder.centerLat,
                          initialFolder.centerLng,
                          label: initialFolder.title,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.80,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: livePhotos.length,
                  itemBuilder: (itemCtx, idx) {
                    final wp = livePhotos[idx];
                    return Card(
                      elevation: 1.5,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: InkWell(
                        onTap: () => _showPhotoDetailModal(context, wp),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPhotoThumb(wp)),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    wp.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('dd/MM/yyyy HH:mm')
                                        .format(wp.timestamp),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPhotoDetailModal(BuildContext context, Waypoint wp) {
    final file = wp.photoPath != null ? File(wp.photoPath!) : null;
    final exists = file != null && file.existsSync();
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (exists)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    file,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                wp.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('EEEE, dd/MM/yyyy HH:mm', 'vi')
                        .format(wp.timestamp),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.gps_fixed,
                      size: 14, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 4),
                  Text(
                    'Toạ độ: ${wp.latitude.toStringAsFixed(5)}, ${wp.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8B5CF6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (wp.note != null && wp.note!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  wp.note!,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ExternalMapService().openGoogleMaps(
                          wp.latitude,
                          wp.longitude,
                          label: wp.name,
                        );
                      },
                      icon: const Icon(Icons.map_outlined,
                          size: 16, color: Colors.blue),
                      label: const Text('Google Maps',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ExternalMapService().openGooglePhotos(
                          lat: wp.latitude,
                          lng: wp.longitude,
                          timestamp: wp.timestamp,
                          placeName: wp.name,
                        );
                      },
                      icon: const Icon(Icons.photo_library_outlined,
                          size: 16, color: Colors.teal),
                      label: const Text('Google Photos',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.teal),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await tripProvider.deleteWaypoint(wp.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Đã xoá ảnh khỏi bộ sưu tập.')),
                        );
                      }
                    },
                    icon:
                        const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'Xoá ảnh này',
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
