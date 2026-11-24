import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/pinned_place.dart';
import '../models/vehicle_type.dart';
import '../providers/map_settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/trip_provider.dart';
import '../services/app_update_service.dart';
import '../services/external_map_service.dart';
import '../widgets/app_update_dialog.dart';
import '../services/goong_service.dart';
import '../services/offline_map_service.dart';
import '../services/openmap_service.dart';
import '../theme/app_theme.dart';
import '../widgets/home_picker_dialog.dart';
import '../widgets/offline_map_preload_dialog.dart';
import '../widgets/pinned_place_dialog.dart';
import '../widgets/vehicle_picker_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _googleKeyController;
  late final TextEditingController _openmapKeyController;
  late final TextEditingController _openmapTileUrlController;
  late String _selectedOpenMapDomain;
  bool _isTestingOpenMap = false;
  int _offlineTileCount = 0;
  int _offlineTileBytes = 0;
  String _currentVersionLabel = '';

  Future<void> _loadCurrentVersion() async {
    final v = await AppUpdateService().getCurrentVersion();
    if (mounted) setState(() => _currentVersionLabel = v.displayVersion);
  }

  Future<void> _editGithubToken() async {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final controller = TextEditingController(text: settings.githubUpdateToken);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GitHub Token cập nhật'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chỉ cần khi kho GitHub ở chế độ Riêng tư. Dùng fine-grained token quyền Contents: Read-only cho đúng kho này.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (saved == true) await settings.setGithubUpdateToken(controller.text.trim());
    controller.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    _googleKeyController = TextEditingController(text: settings.googleApiKey);
    _openmapKeyController = TextEditingController(text: settings.openmapApiKey);
    _openmapTileUrlController = TextEditingController(text: settings.openmapCustomTileUrl);
    _selectedOpenMapDomain = settings.openmapDomain;
    _loadOfflineStats();
  }

  Future<void> _loadOfflineStats() async {
    final stats = await OfflineMapService().getOfflineStats();
    if (mounted) {
      setState(() {
        _offlineTileCount = stats.count;
        _offlineTileBytes = stats.totalBytes;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _googleKeyController.dispose();
    _openmapKeyController.dispose();
    _openmapTileUrlController.dispose();
    super.dispose();
  }

  void _saveGoogleKey() {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    settings.updateGoogleApiKey(_googleKeyController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu cấu hình Google Maps API Key!'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _saveOpenMapConfig() {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    settings.updateOpenMapConfig(
      apiKey: _openmapKeyController.text.trim(),
      domain: _selectedOpenMapDomain,
      customTileUrl: _openmapTileUrlController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu cấu hình OpenMap.vn / NDAMaps!'),
        backgroundColor: Colors.deepPurple,
      ),
    );
  }

  Future<void> _testOpenMapConnection() async {
    final testKey = _openmapKeyController.text.trim();
    if (testKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập OpenMap / NDAMaps API Key trước khi kiểm tra.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isTestingOpenMap = true);
    OpenMapService().setDomain(_selectedOpenMapDomain);
    OpenMapService().setCustomTileUrl(_openmapTileUrlController.text.trim());

    final styleResult = await OpenMapService().testStyleConnection(customKey: testKey);
    final addr = await OpenMapService().reverseGeocode(21.03431, 105.78823, customKey: testKey);
    if (!mounted) return;
    setState(() => _isTestingOpenMap = false);

    final anyOk = styleResult.ok || (addr != null && addr.isNotEmpty);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(anyOk ? Icons.check_circle : Icons.error_outline, color: anyOk ? Colors.green : Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text('Kiểm tra $_selectedOpenMapDomain')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Bản đồ Vector (Map Tiles):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              styleResult.ok ? '✅ ${styleResult.message}' : '❌ ${styleResult.message}',
              style: TextStyle(fontSize: 12.5, color: styleResult.ok ? Colors.green.shade800 : Colors.redAccent),
            ),
            const SizedBox(height: 12),
            const Text('2. Tra cứu địa chỉ (Geocoding):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            if (addr != null && addr.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text('✅ $addr', style: const TextStyle(fontSize: 12)),
              )
            else
              const Text('❌ Không nhận được kết quả Geocoding.', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MapSettingsProvider>(context);
    final tripProvider = Provider.of<TripProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt Bản Đồ & API'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section: Geocoding / Address Lookup Engine Provider
          _sectionHeader('NGUỒN TRA CỨU ĐỊA CHỈ & TOẠ ĐỘ (GEOCODING)', Icons.hub_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chọn dịch vụ tự động đặt tên đường, phường/xã từ toạ độ GPS:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.map, size: 16),
                        label: const Text('Google Maps'),
                        selected: settings.activeEngine == MapEngineProvider.google,
                        selectedColor: Colors.blue.withOpacity(0.2),
                        onSelected: (selected) {
                          if (selected) settings.setActiveEngine(MapEngineProvider.google);
                        },
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.explore_outlined, size: 16),
                        label: const Text('OpenMap.vn / NDAMaps'),
                        selected: settings.activeEngine == MapEngineProvider.openmap,
                        selectedColor: Colors.deepPurple.withOpacity(0.2),
                        onSelected: (selected) {
                          if (selected) settings.setActiveEngine(MapEngineProvider.openmap);
                        },
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.offline_bolt_outlined, size: 16),
                        label: const Text('Chỉ Ngoại Tuyến'),
                        selected: settings.activeEngine == MapEngineProvider.offline,
                        selectedColor: Colors.teal.withOpacity(0.2),
                        onSelected: (selected) {
                          if (selected) settings.setActiveEngine(MapEngineProvider.offline);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    settings.activeEngine == MapEngineProvider.google
                        ? 'Đang ưu tiên Google Maps (với dự phòng Nominatim & Ngoại tuyến).'
                        : settings.activeEngine == MapEngineProvider.openmap
                            ? 'Đang sử dụng OpenMap.vn / NDAMaps (${settings.openmapDomain}) để dịch ngược địa chỉ hành chính Việt Nam mới.'
                            : 'Chế độ Ngoại Tuyến 100%: Không gửi bất kỳ yêu cầu mạng nào, tự động nhận diện 63 Tỉnh/Thành cục bộ.',
                    style: TextStyle(
                      fontSize: 12,
                      color: settings.activeEngine == MapEngineProvider.google
                          ? Colors.blue
                          : settings.activeEngine == MapEngineProvider.openmap
                              ? Colors.deepPurple
                              : Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Google Maps Configuration
          _sectionHeader('GOOGLE MAPS (ĐƯỜNG PHỐ, VỆ TINH, ĐỊA HÌNH)', Icons.map_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.25)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline, size: 18, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bản đồ Google Maps (Đường phố, Vệ tinh lai, Vệ tinh thuần, Địa hình tiếng Việt) hoạt động hiển thị NGAY LẬP TỨC mà không cần nhập API Key!',
                            style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _googleKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Google Geocoding API Key (Tùy chọn)',
                      hintText: 'Dán API Key nếu bạn muốn tra cứu số nhà qua Google Cloud',
                      prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.blue),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _saveGoogleKey,
                        icon: const Icon(Icons.save_outlined, size: 16),
                        label: const Text('Lưu Google Key', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: OpenMap.vn / NDAMaps.vn Configuration
          _sectionHeader('OPENMAP.VN & NDAMAPS.VN (BẢN ĐỒ SỐ VIỆT NAM)', Icons.explore_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hỗ trợ hệ thống bản đồ số quốc gia OpenMap.vn và NDAMaps.vn (hỗ trợ chuẩn địa chính mới sáp nhập admin_v2).',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Cổng API:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('openmap.vn'),
                        selected: _selectedOpenMapDomain == 'openmap.vn',
                        selectedColor: Colors.deepPurple.withOpacity(0.2),
                        onSelected: (s) {
                          if (s) setState(() => _selectedOpenMapDomain = 'openmap.vn');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('ndamaps.vn'),
                        selected: _selectedOpenMapDomain == 'ndamaps.vn',
                        selectedColor: Colors.deepPurple.withOpacity(0.2),
                        onSelected: (s) {
                          if (s) setState(() => _selectedOpenMapDomain = 'ndamaps.vn');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openmapKeyController,
                    decoration: const InputDecoration(
                      labelText: 'OpenMap / NDAMaps API Key',
                      hintText: 'Nhập apikey từ openmap.vn hoặc ndamaps.vn',
                      prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.deepPurple),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openmapTileUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL Vector Style JSON tùy chỉnh (Tùy chọn)',
                      hintText: 'Mặc định: maptiles.{domain}/styles/day-v1/style.json',
                      prefixIcon: Icon(Icons.link, color: Colors.deepPurple),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('https://enterprise.openmap.vn/'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('Lấy Key (enterprise)', style: TextStyle(fontSize: 12)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isTestingOpenMap ? null : _testOpenMapConnection,
                        icon: _isTestingOpenMap
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering, size: 16, color: Colors.deepPurple),
                        label: const Text('Thử kết nối', style: TextStyle(fontSize: 12, color: Colors.deepPurple)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _saveOpenMapConfig,
                        icon: const Icon(Icons.save_outlined, size: 16),
                        label: const Text('Lưu OpenMap', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Map Style Preference
          _sectionHeader('GIAO DIỆN BẢN ĐỒ', Icons.layers_outlined),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Kiểu bản đồ hiển thị'),
                  subtitle: Text(_getStyleName(settings.mapStyle)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _pickMapStyle(context, settings),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Tự động căn giữa vị trí GPS'),
                  subtitle: const Text('Luôn di chuyển camera theo vị trí của bạn khi ghi lại'),
                  value: settings.autoCenter,
                  activeColor: AppTheme.primary,
                  onChanged: (val) => settings.toggleAutoCenter(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section: Vehicle & Compass Rotation
          _sectionHeader('BIỂU TƯỢNG PHƯƠNG TIỆN & LA BÀN', settings.vehicleType.icon),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: settings.vehicleColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(settings.vehicleType.icon, color: Colors.white, size: 22),
                  ),
                  title: const Text('Biểu tượng & màu phương tiện'),
                  subtitle: Text('${settings.vehicleType.label} • Hiển thị khi bắt đầu hành trình'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => VehiclePickerSheet.show(context),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Xoay bản đồ theo hướng di chuyển'),
                  subtitle: const Text(
                    'Trong lúc ghi hành trình, bản đồ tự động xoay theo hướng bạn đang chạy; mũi tên phương tiện luôn chỉ hướng điện thoại.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: settings.rotateMapWithHeading,
                  activeColor: AppTheme.primary,
                  onChanged: (val) => settings.setRotateMapWithHeading(val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section: Home Pin ("Nhà")
          _sectionHeader('ĐỊA ĐIỂM "NHÀ" (HOME PIN)', Icons.home_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.hasHome
                        ? 'Đã ghim vị trí Nhà: ${settings.homeLat!.toStringAsFixed(5)}, ${settings.homeLng!.toStringAsFixed(5)} (Bán kính ${settings.homeRadiusMeters}m)'
                        : 'Chưa thiết lập vị trí Nhà. Khi ghim Nhà, các chuyến đi bắt đầu hoặc kết thúc gần Nhà sẽ tự động ghi nhận tại Nhà.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: settings.hasHome ? const Color(0xFFB45309) : Colors.black87,
                      fontWeight: settings.hasHome ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(settings.hasHome ? 'Đổi vị trí Nhà trên bản đồ' : 'Ghim Nhà trên bản đồ'),
                        onPressed: () => HomePickerDialog.show(context),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.my_location_rounded, size: 17),
                        label: const Text('Dùng vị trí hiện tại'),
                        onPressed: () async {
                          final tracking = Provider.of<TrackingProvider>(context, listen: false);
                          final pos = tracking.currentPosition;
                          if (pos == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Chưa có tín hiệu GPS hiện tại. Hãy chọn trực tiếp trên bản đồ.')),
                              );
                            }
                            return;
                          }
                          await settings.setHome(pos.latitude, pos.longitude);
                          tracking.setHomeConfig(
                            lat: pos.latitude,
                            lng: pos.longitude,
                            radiusMeters: settings.homeRadiusMeters,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã đặt vị trí hiện tại làm "Nhà"!')),
                            );
                          }
                        },
                      ),
                      if (settings.hasHome)
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          label: const Text('Xoá ghim Nhà', style: TextStyle(color: Colors.redAccent)),
                          onPressed: () async {
                            final tracking = Provider.of<TrackingProvider>(context, listen: false);
                            await settings.clearHome();
                            tracking.setHomeConfig(lat: null, lng: null);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bán kính nhận diện quanh Nhà:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [20, 30, 50, 100, 150].map((m) {
                      final isSel = settings.homeRadiusMeters == m;
                      return ChoiceChip(
                        label: Text('${m}m'),
                        selected: isSel,
                        selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                        onSelected: (_) async {
                          final tracking = Provider.of<TrackingProvider>(context, listen: false);
                          await settings.setHomeRadius(m);
                          tracking.setHomeConfig(
                            lat: settings.homeLat,
                            lng: settings.homeLng,
                            radiusMeters: m,
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Custom Pinned Places (Công ty, Quán quen, Trường học...)
          _sectionHeader('ĐỊA ĐIỂM ĐÃ GHIM KHÁC (CÔNG TY, QUÁN QUEN...)', Icons.add_location_alt_rounded),
          Consumer2<TripProvider, TrackingProvider>(
            builder: (ctx, tripProvider, tracking, _) {
              final places = tripProvider.pinnedPlaces;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ghim thêm nhiều địa điểm quan trọng với biểu tượng riêng (Công ty, Trường học, Quán quen...). Hành trình đi/về các điểm này cũng tự động ghi tên địa điểm.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      if (places.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Chưa có địa điểm ghim nào khác. Bạn có thể bấm nút bên dưới hoặc nhấn giữ trực tiếp lên bản đồ.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      else
                        ...places.map((p) {
                          final color = p.category.color;
                          return Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.14),
                                  child: Icon(p.category.icon, color: color, size: 20),
                                ),
                                title: Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  '${p.category.label} • Bán kính ${p.radiusMeters}m',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 19),
                                      tooltip: 'Sửa',
                                      onPressed: () => PinnedPlaceDialog.show(ctx, existingPlace: p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                                      tooltip: 'Xoá',
                                      onPressed: () async {
                                        await tripProvider.deletePinnedPlace(p.id);
                                        tracking.setPinnedPlaces(tripProvider.pinnedPlaces);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                          );
                        }),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                        icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                        label: const Text('Ghim địa điểm mới trên bản đồ'),
                        onPressed: () => PinnedPlaceDialog.show(ctx, allowHomeChoice: false),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Section: Offline Map Preload (Tải sẵn bản đồ ngoại tuyến)
          _sectionHeader('BẢN ĐỒ NGOẠI TUYẾN (DÙNG KHÔNG CẦN INTERNET)', Icons.download_for_offline_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tải sẵn các ô bản đồ khu vực hoặc tỉnh/thành phố để xem và thu phóng khi đi rừng, leo núi, hoặc mất sóng 4G/Wifi.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sd_storage_outlined, color: Colors.blue, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dung lượng bản đồ ngoại tuyến đã lưu:',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$_offlineTileCount ô bản đồ (${_formatBytes(_offlineTileBytes)})',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (ctx) => const OfflineMapPreloadDialog(),
                            );
                            _loadOfflineStats();
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Tải bản đồ khu vực', style: TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (_offlineTileCount > 0) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Xác nhận xóa bộ nhớ đệm?'),
                                content: const Text('Thao tác này sẽ xóa tất cả các ô bản đồ đã tải về máy.'),
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
                              await _loadOfflineStats();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Đã dọn sạch bộ nhớ bản đồ ngoại tuyến.')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          label: const Text('Dọn dẹp', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Tracking Precision
          _sectionHeader('ĐỘ CHÍNH XÁC GPS', Icons.gps_fixed),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Khoảng cách tối thiểu ghi nhận điểm mới:'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [5, 10, 20].map((dist) {
                      final isSelected = settings.distanceFilter == dist;
                      return ChoiceChip(
                        label: Text('$dist mét${dist == 5 ? ' (Chi tiết)' : ''}'),
                        selected: isSelected,
                        selectedColor: AppTheme.primary.withOpacity(0.2),
                        onSelected: (_) => settings.setDistanceFilter(dist),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Background Auto-Tracking
          _sectionHeader('THEO DÕI CHẠY NGẦM & TỰ ĐỘNG GHI', Icons.directions_run_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Tự động tạo hành trình khi chạy ngầm'),
                    subtitle: const Text(
                      'Khi di chuyển phạm vi lớn với tốc độ cao liên tục, ứng dụng tự mở hành trình mới (chống nhận nhầm khi đứng yên lệch GPS hoặc đi bộ quanh 1 chỗ)',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: settings.backgroundAutoTrack,
                    activeColor: AppTheme.primary,
                    onChanged: (val) => settings.setBackgroundAutoTrack(val),
                  ),
                  if (settings.backgroundAutoTrack) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.verified_user_outlined, size: 17, color: AppTheme.primary),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Bộ lọc thông minh chỉ kích hoạt khi rời khỏi điểm neo đủ xa và duy trì tốc độ cao liên tục >= 8 giây, loại bỏ nhiễu GPS trong nhà và đi bộ quanh 1 khu vực.',
                                    style: TextStyle(fontSize: 11.5, color: Colors.black87, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Tốc độ tối thiểu kích hoạt:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [10.0, 12.0, 15.0, 20.0].map((spd) {
                              final isSelected = settings.autoTrackMinSpeedKmh == spd;
                              return ChoiceChip(
                                label: Text('${spd.toInt()} km/h'),
                                selected: isSelected,
                                selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                                onSelected: (_) => settings.setAutoTrackMinSpeedKmh(spd),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Phạm vi dịch chuyển tối thiểu:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [100, 150, 250, 400].map((rng) {
                              final isSelected = settings.autoTrackMinRangeMeters == rng;
                              return ChoiceChip(
                                label: Text('${rng}m'),
                                selected: isSelected,
                                selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                                onSelected: (_) => settings.setAutoTrackMinRangeMeters(rng),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Auto Stop when stationary
          _sectionHeader('TỰ ĐỘNG TẮT GHI KHI DỪNG CHÂN LÂU', Icons.timer_off_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Tự động kết thúc khi dừng chân lâu'),
                    subtitle: const Text(
                      'Tự động lưu và dừng ghi vị trí nếu bạn ở yên một chỗ để tiết kiệm pin',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: settings.autoStopWhenStationary,
                    activeColor: AppTheme.primary,
                    onChanged: (val) => settings.setAutoStopWhenStationary(val),
                  ),
                  if (settings.autoStopWhenStationary) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thời gian dừng trước khi tự ngắt:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [5, 10, 15, 30, 60].map((mins) {
                              final isSelected = settings.autoStopStationaryMinutes == mins;
                              return ChoiceChip(
                                label: Text(mins == 60 ? '1 tiếng' : '$mins phút'),
                                selected: isSelected,
                                selectedColor: AppTheme.primary.withOpacity(0.2),
                                onSelected: (_) => settings.setAutoStopStationaryMinutes(mins),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: Google Drive & Privacy Backup
          _sectionHeader('GOOGLE DRIVE CÁ NHÂN & BẢO MẬT', Icons.cloud_sync_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 20, color: Colors.green),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Quyền riêng tư tuyệt đối: Dữ liệu vị trí và hành trình chỉ lưu trong máy của bạn. Khi sao lưu, dữ liệu chuyển thẳng tới Google Drive cá nhân của bạn mà không qua bất kỳ máy chủ trung gian nào của nhà phát triển.',
                            style: TextStyle(fontSize: 11.5, color: Colors.black87, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cloud_upload_rounded, color: Colors.blue),
                    ),
                    title: const Text('Sao lưu lên Google Drive (1 chạm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Xuất file & mở cửa sổ Google Drive để lưu tự động', style: TextStyle(fontSize: 12)),
                    onTap: () => _handleBackupToDrive(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings_backup_restore_rounded, color: Colors.teal),
                    ),
                    title: const Text('Khôi phục dữ liệu từ file sao lưu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Khôi phục hành trình & điểm khám phá từ file JSON', style: TextStyle(fontSize: 12)),
                    onTap: () => _handleRestoreBackup(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_to_drive_outlined, color: Colors.amber),
                    ),
                    title: const Text('Mở ứng dụng Google Drive của bạn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Truy cập thư mục cá nhân trên Google Drive', style: TextStyle(fontSize: 12)),
                    onTap: () => ExternalMapService().openGoogleDrivePersonal(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section: App Update (GitHub Releases)
          _sectionHeader('CẬP NHẬT ỨNG DỤNG', Icons.system_update_rounded),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.system_update_rounded, color: AppTheme.primary),
                  ),
                  title: const Text('Kiểm tra cập nhật', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Phiên bản hiện tại: ${_currentVersionLabel.isEmpty ? '...' : _currentVersionLabel}. Có bản mới sẽ hỏi tải về và tự mở trình cài đặt.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => AppUpdateDialog.checkAndPrompt(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.key_rounded, color: Colors.orange),
                  title: const Text('GitHub Token (kho riêng tư)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    settings.githubUpdateToken.isEmpty ? 'Chưa nhập — cần nếu kho GitHub ở chế độ Private' : 'Đã lưu token cập nhật',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: _editGithubToken,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section: Data & Reset
          _sectionHeader('DỮ LIỆU & BỘ NHỚ', Icons.storage_rounded),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Xoá toàn bộ dữ liệu khám phá', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Xoá tất cả chuyến đi và đặt lại bản đồ về ban đầu'),
                  onTap: () => _confirmClearAll(context, tripProvider),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          Center(
            child: Text(
              'Bản Đồ Hành Trình ${_currentVersionLabel.isEmpty ? '' : _currentVersionLabel} • Google Maps & OpenMap.vn Edition',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _getStyleName(MapStyleType style) {
    switch (style) {
      case MapStyleType.googleStreets:
        return 'Google Maps Đường Phố (Tiếng Việt - Khuyên dùng)';
      case MapStyleType.googleHybrid:
        return 'Google Maps Vệ Tinh Lai (Vệ tinh + Tên đường)';
      case MapStyleType.googleSatellite:
        return 'Google Maps Vệ Tinh Thuần';
      case MapStyleType.googleTerrain:
        return 'Google Maps Địa Hình';
      case MapStyleType.openmapVn:
        return 'OpenMap.vn / NDAMaps (Vector Ban ngày - day-v1)';
      case MapStyleType.openmapVnNight:
        return 'OpenMap.vn / NDAMaps (Vector Ban đêm - night-v1)';
      case MapStyleType.openmapVnSatellite:
        return 'OpenMap.vn / NDAMaps (Vector Vệ tinh - satellite-v1)';
      case MapStyleType.openStreetMap:
        return 'OpenStreetMap Tiêu Chuẩn (Đã fix chính sách)';
      case MapStyleType.osmHot:
        return 'OpenStreetMap Tiếng Việt (HOT)';
      case MapStyleType.esriSatellite:
        return 'Ảnh Vệ Tinh ESRI World Imagery';
      case MapStyleType.topo:
        return 'Bản Đồ Địa Hình (OpenTopoMap)';
    }
  }

  void _pickMapStyle(BuildContext context, MapSettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Chọn kiểu bản đồ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ...MapStyleType.values.map(
                (style) => ListTile(
                  title: Text(_getStyleName(style), style: const TextStyle(fontSize: 14)),
                  trailing: settings.mapStyle == style ? const Icon(Icons.check, color: AppTheme.primary) : null,
                  onTap: () {
                    settings.setMapStyle(style);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearAll(BuildContext context, TripProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xoá toàn bộ dữ liệu'),
        content: const Text('Hành động này sẽ xoá sạch mọi chuyến đi, toạ độ GPS và điểm mốc. Bạn không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.clearAllData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xoá sạch dữ liệu.')),
                );
              }
            },
            child: const Text('Xác nhận xoá', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleBackupToDrive(BuildContext context) async {
    try {
      final file = await ExternalMapService().createFullBackupFile();
      if (!context.mounted) return;

      // Automatically trigger the Android native Share Sheet (opens "Save to Drive" / "Lưu vào Drive")
      ExternalMapService().shareBackupToGoogleDrive(file);

      final fileName = file.path.split(Platform.pathSeparator).last;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Đã xuất file sao lưu!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Hệ thống đã mở cửa sổ để tải lên Drive', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_open_rounded, size: 18, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vị trí lưu trên máy: Thư mục Download (Tải về)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Đường dẫn đầy đủ: ${file.path}',
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tên file: $fileName',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '💡 Cách lưu tự động:\nTrong bảng chọn vừa hiện lên, bạn chỉ cần chạm vào biểu tượng "Google Drive" (hoặc "Lưu vào Drive"), chọn thư mục cá nhân và bấm "Lưu". File sẽ được tải lên Google Drive của bạn ngay lập tức!',
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          ExternalMapService().shareBackupToGoogleDrive(file);
                        },
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Mở lại hộp thoại Drive'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          ExternalMapService().openGoogleDrivePersonal();
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Mở Google Drive'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleRestoreBackup(BuildContext context) async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final files = await ExternalMapService().getExistingBackupFiles();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_backup_restore_rounded, color: AppTheme.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Khôi phục dữ liệu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Chọn file sao lưu có sẵn trên máy để phục hồi', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (files.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Chưa tìm thấy file sao lưu nào trong thư mục Download / Tệp của máy.\nNếu bạn đã lưu file trên Google Drive, hãy tải file về máy rồi thử lại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ),
              ] else ...[
                const Text('Các bản sao lưu tìm thấy trên máy:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (_, index) {
                      final f = files[index];
                      final name = f.uri.pathSegments.last;
                      final sizeKb = (f.lengthSync() / 1024).toStringAsFixed(1);
                      final modified = DateFormat('dd/MM/yyyy HH:mm').format(f.lastModifiedSync());

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined, color: AppTheme.primary),
                          title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$sizeKb KB • $modified', style: const TextStyle(fontSize: 11)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              _restoreFromFile(context, f, tripProvider);
                            },
                            child: const Text('Khôi phục', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _restoreFromFile(BuildContext context, File file, TripProvider tripProvider) async {
    try {
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final success = await tripProvider.importBackupJson(data);

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Khôi phục toàn bộ hành trình thành công!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể đọc file sao lưu này.'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi khôi phục: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
