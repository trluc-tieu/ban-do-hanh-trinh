import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trip.dart';
import '../models/waypoint.dart';
import 'database_service.dart';

class ExternalMapService {
  static final ExternalMapService _instance = ExternalMapService._internal();
  factory ExternalMapService() => _instance;
  ExternalMapService._internal();

  /// Open exact coordinates in Google Maps App or Web
  Future<bool> openGoogleMaps(double lat, double lng, {String? label}) async {
    final query = label != null ? Uri.encodeComponent(label) : '$lat,$lng';
    // Native geo URI on Android
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($query)');
    // Universal web Google Maps link
    final webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    try {
      if (await canLaunchUrl(geoUri)) {
        return await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    return await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  /// Open Google Photos filtered by place name, coordinates, or date
  Future<bool> openGooglePhotos({double? lat, double? lng, DateTime? timestamp, String? placeName}) async {
    String searchKeyword = '';
    if (placeName != null && placeName.isNotEmpty) {
      searchKeyword = placeName;
    } else if (timestamp != null) {
      searchKeyword = DateFormat('yyyy-MM-dd').format(timestamp);
    } else if (lat != null && lng != null) {
      searchKeyword = '$lat, $lng';
    }

    final photosUri = Uri.parse('https://photos.google.com/search/${Uri.encodeComponent(searchKeyword)}');
    return await launchUrl(photosUri, mode: LaunchMode.externalApplication);
  }

  /// Open device photo gallery
  Future<bool> openDeviceGallery() async {
    final uri = Uri.parse('content://media/internal/images/media');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (_) {}
    return openGooglePhotos();
  }

  /// Open user's personal Google Drive (Direct, 100% private, no server intermediary)
  Future<bool> openGoogleDrivePersonal() async {
    final driveAppUri = Uri.parse('https://drive.google.com/drive/my-drive');
    return await launchUrl(driveAppUri, mode: LaunchMode.externalApplication);
  }

  /// Export complete database to visible Download directory
  Future<File> createFullBackupFile() async {
    final data = await DatabaseService().exportFullDatabaseJson();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    // Save to visible public Download folder so user can easily find it in "Files / Tệp"
    Directory? targetDir;
    if (Platform.isAndroid) {
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (publicDownload.existsSync()) {
        targetDir = publicDownload;
      }
    }

    // Fallbacks if public Download is inaccessible
    if (targetDir == null) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) targetDir = extDir;
      } catch (_) {}
    }
    targetDir ??= await getApplicationDocumentsDirectory();

    final fileName = 'ban_do_hanh_trinh_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
    final file = File('${targetDir.path}/$fileName');
    return await file.writeAsString(jsonStr);
  }

  /// Directly upload / share backup file to personal Google Drive via native Android Share Sheet
  Future<ShareResult> shareBackupToGoogleDrive(File backupFile) async {
    final fileName = backupFile.uri.pathSegments.isNotEmpty
        ? backupFile.uri.pathSegments.last
        : 'ban_do_hanh_trinh_backup.json';

    return await Share.shareXFiles(
      [
        XFile(
          backupFile.path,
          mimeType: 'application/json',
          name: fileName,
        ),
      ],
      text: 'Sao lưu dữ liệu Bản Đồ Hành Trình (Tải lên Google Drive cá nhân)',
      subject: fileName,
    );
  }

  /// Find existing backup files in Download and app directories
  Future<List<File>> getExistingBackupFiles() async {
    final List<File> files = [];

    // Check public Download directory
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        final list = downloadDir.listSync();
        for (final item in list) {
          if (item is File && item.path.contains('ban_do_hanh_trinh_backup') && item.path.endsWith('.json')) {
            files.add(item);
          }
        }
      }
    } catch (_) {}

    // Check app documents directory
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final list = docDir.listSync();
      for (final item in list) {
        if (item is File && item.path.contains('ban_do_hanh_trinh_backup') && item.path.endsWith('.json')) {
          if (!files.any((f) => f.path == item.path)) {
            files.add(item);
          }
        }
      }
    } catch (_) {}

    files.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    return files;
  }

  /// Legacy helper for specific trip/waypoint subsets
  Future<File> createBackupFile({required List<Trip> trips, required List<Waypoint> waypoints}) async {
    return createFullBackupFile();
  }
}
