import 'dart:io';
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/province_stats.dart';
import '../models/waypoint.dart';
import 'database_service.dart';
import 'goong_service.dart';
import 'nearby_places_service.dart';

class PhotoFolderCluster {
  final String id;
  final String title;
  final String province;
  final double centerLat;
  final double centerLng;
  final List<Waypoint> photos;
  final DateTime latestTimestamp;

  const PhotoFolderCluster({
    required this.id,
    required this.title,
    required this.province,
    required this.centerLat,
    required this.centerLng,
    required this.photos,
    required this.latestTimestamp,
  });

  Waypoint get coverPhoto => photos.first;
  int get count => photos.length;
}

class PhotoDiscoveryResult {
  final int totalSelected;
  final int geotaggedFound;
  final List<Waypoint> newWaypoints;
  final String? diagnosticNote;

  PhotoDiscoveryResult({
    required this.totalSelected,
    required this.geotaggedFound,
    required this.newWaypoints,
    this.diagnosticNote,
  });
}

class PhotoDiscoveryService {
  static final PhotoDiscoveryService _instance = PhotoDiscoveryService._internal();
  factory PhotoDiscoveryService() => _instance;
  PhotoDiscoveryService._internal();

  final DatabaseService _dbService = DatabaseService();
  final GoongService _goongService = GoongService();
  final ImagePicker _picker = ImagePicker();

  /// Parse GPS coordinates from raw bytes
  Future<Map<String, dynamic>?> extractExifLocationFromBytes(
    Uint8List bytes, {
    String? filePath,
    DateTime? fallbackTimestamp,
  }) async {
    try {
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) return null;

      IfdTag? latTag;
      IfdTag? latRefTag;
      IfdTag? lngTag;
      IfdTag? lngRefTag;
      IfdTag? dateTag;

      for (final entry in data.entries) {
        final keyLower = entry.key.toLowerCase();
        if (keyLower.contains('latitude') && !keyLower.contains('ref')) {
          latTag ??= entry.value;
        } else if (keyLower.contains('latituderef') || (keyLower.contains('latitude') && keyLower.contains('ref'))) {
          latRefTag ??= entry.value;
        } else if (keyLower.contains('longitude') && !keyLower.contains('ref')) {
          lngTag ??= entry.value;
        } else if (keyLower.contains('longituderef') || (keyLower.contains('longitude') && keyLower.contains('ref'))) {
          lngRefTag ??= entry.value;
        } else if (keyLower.contains('datetimeoriginal') || keyLower.contains('datetime')) {
          dateTag ??= entry.value;
        }
      }

      if (latTag == null || lngTag == null) return null;

      final lat = ratioListToDecimal(
        latTag.values,
        latRefTag?.printable ?? latRefTag?.values.toString(),
        latTag.printable,
      );
      final lng = ratioListToDecimal(
        lngTag.values,
        lngRefTag?.printable ?? lngRefTag?.values.toString(),
        lngTag.printable,
      );

      final timestamp = parseExifDate(dateTag?.printable) ?? fallbackTimestamp ?? DateTime.now();

      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        return {
          'latitude': lat,
          'longitude': lng,
          'timestamp': timestamp,
        };
      }
    } catch (_) {}
    return null;
  }

  /// Parse GPS coordinates from an image file using EXIF
  Future<Map<String, dynamic>?> extractExifLocation(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await extractExifLocationFromBytes(
        bytes,
        filePath: file.path,
        fallbackTimestamp: file.lastModifiedSync(),
      );
    } catch (_) {}
    return null;
  }

  /// Pick raw original photo files without Android Photo Picker EXIF redaction
  /// (Uses ACTION_GET_CONTENT which guarantees Android does NOT strip GPS EXIF)
  Future<PhotoDiscoveryResult> pickOriginalPhotoFiles() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.image,
    );

    if (files.isEmpty) {
      return PhotoDiscoveryResult(totalSelected: 0, geotaggedFound: 0, newWaypoints: []);
    }

    final List<Waypoint> newWaypoints = [];
    final tempDir = await getTemporaryDirectory();

    for (final pFile in files) {
      Uint8List? bytes;
      try {
        bytes = await pFile.readAsBytes();
      } catch (_) {
        if (pFile.path != null) {
          try {
            bytes = await File(pFile.path!).readAsBytes();
          } catch (_) {}
        }
      }

      if (bytes == null || bytes.isEmpty) continue;

      String? localPath = pFile.path;
      if (localPath == null || !File(localPath).existsSync()) {
        try {
          final tempFile = File('${tempDir.path}/${pFile.name}');
          await tempFile.writeAsBytes(bytes);
          localPath = tempFile.path;
        } catch (_) {}
      }

      final geo = await extractExifLocationFromBytes(
        bytes,
        filePath: localPath,
        fallbackTimestamp: DateTime.now(),
      );

      if (geo != null) {
        final double lat = geo['latitude'];
        final double lng = geo['longitude'];
        final DateTime time = geo['timestamp'];

        String? address;
        try {
          address = await _goongService.reverseGeocode(lat, lng);
        } catch (_) {}

        final placeName = address != null && address.isNotEmpty
            ? address.split(',').first.trim()
            : 'Ảnh gốc • ${DateFormat('dd/MM/yyyy HH:mm').format(time)}';

        final wp = Waypoint(
          id: const Uuid().v4(),
          tripId: 'photo-discovery',
          name: placeName,
          note: address ?? 'Toạ độ: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
          latitude: lat,
          longitude: lng,
          timestamp: time,
          photoPath: localPath,
        );

        await _dbService.insertWaypoint(wp);
        newWaypoints.add(wp);
      }
    }

    return PhotoDiscoveryResult(
      totalSelected: files.length,
      geotaggedFound: newWaypoints.length,
      newWaypoints: newWaypoints,
    );
  }

  /// Pick photos from Google Photos or Device Gallery via system photo picker
  Future<PhotoDiscoveryResult> pickAndImportPhotos() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) {
      return PhotoDiscoveryResult(totalSelected: 0, geotaggedFound: 0, newWaypoints: []);
    }

    final List<Waypoint> newWaypoints = [];

    for (final xfile in images) {
      final file = File(xfile.path);
      final geo = await extractExifLocation(file);

      if (geo != null) {
        final double lat = geo['latitude'];
        final double lng = geo['longitude'];
        final DateTime time = geo['timestamp'];

        String? address;
        try {
          address = await _goongService.reverseGeocode(lat, lng);
        } catch (_) {}

        final placeName = address != null && address.isNotEmpty
            ? address.split(',').first.trim()
            : 'Ảnh chụp • ${DateFormat('dd/MM/yyyy HH:mm').format(time)}';

        final wp = Waypoint(
          id: const Uuid().v4(),
          tripId: 'photo-discovery',
          name: placeName,
          note: address ?? 'Toạ độ: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
          latitude: lat,
          longitude: lng,
          timestamp: time,
          photoPath: file.path,
        );

        await _dbService.insertWaypoint(wp);
        newWaypoints.add(wp);
      }
    }

    return PhotoDiscoveryResult(
      totalSelected: images.length,
      geotaggedFound: newWaypoints.length,
      newWaypoints: newWaypoints,
    );
  }

  /// Scan local device camera folder for geotagged photos
  Future<PhotoDiscoveryResult> scanDeviceCameraPhotos() async {
    try {
      if (Platform.isAndroid) {
        if (await Permission.photos.isDenied) {
          await Permission.photos.request();
        }
        if (await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
        if (await Permission.accessMediaLocation.isDenied) {
          await Permission.accessMediaLocation.request();
        }
      }
    } catch (_) {}

    final List<File> candidateFiles = [];
    final scannedPaths = <String>{};

    final directoriesToScan = [
      Directory('/storage/emulated/0/DCIM/Camera'),
      Directory('/storage/emulated/0/DCIM/100ANDRO'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/Pictures/Camera'),
      Directory('/storage/emulated/0/Pictures'),
    ];

    for (final dir in directoriesToScan) {
      try {
        if (dir.existsSync()) {
          final list = dir.listSync(recursive: true, followLinks: false);
          for (final item in list) {
            if (item is File && !scannedPaths.contains(item.path)) {
              final lower = item.path.toLowerCase();
              if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.heic')) {
                scannedPaths.add(item.path);
                candidateFiles.add(item);
                if (candidateFiles.length >= 250) break;
              }
            }
          }
        }
      } catch (_) {}
      if (candidateFiles.length >= 250) break;
    }

    // Sort newest files first
    try {
      candidateFiles.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });
    } catch (_) {}

    // Get already imported photo paths
    final existingWps = await _dbService.getPhotoWaypoints();
    final existingPaths = existingWps.map((w) => w.photoPath).whereType<String>().toSet();

    final List<Waypoint> newWaypoints = [];

    for (final file in candidateFiles) {
      if (existingPaths.contains(file.path)) continue;

      final geo = await extractExifLocation(file);
      if (geo != null) {
        final double lat = geo['latitude'];
        final double lng = geo['longitude'];
        final DateTime time = geo['timestamp'];

        String? address;
        try {
          address = await _goongService.reverseGeocode(lat, lng);
        } catch (_) {}

        final placeName = address != null && address.isNotEmpty
            ? address.split(',').first.trim()
            : 'Ảnh máy • ${DateFormat('dd/MM/yyyy HH:mm').format(time)}';

        final wp = Waypoint(
          id: const Uuid().v4(),
          tripId: 'photo-discovery',
          name: placeName,
          note: address ?? 'Toạ độ: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
          latitude: lat,
          longitude: lng,
          timestamp: time,
          photoPath: file.path,
        );

        await _dbService.insertWaypoint(wp);
        newWaypoints.add(wp);
      }
    }

    return PhotoDiscoveryResult(
      totalSelected: candidateFiles.length,
      geotaggedFound: newWaypoints.length,
      newWaypoints: newWaypoints,
    );
  }

  /// Helper to convert EXIF GPS ratio list to decimal degrees
  static double? ratioListToDecimal(dynamic values, String? ref, [String? printable]) {
    if (values == null && printable == null) return null;
    try {
      List<dynamic>? list;
      if (values is IfdValues) {
        list = values.toList();
      } else if (values is List) {
        list = values;
      }

      if (list != null && list.isNotEmpty) {
        double deg = list.isNotEmpty ? ratioToDouble(list[0]) : 0.0;
        double min = list.length > 1 ? ratioToDouble(list[1]) : 0.0;
        double sec = list.length > 2 ? ratioToDouble(list[2]) : 0.0;

        double result = deg + (min / 60.0) + (sec / 3600.0);
        if (ref != null && (ref.toUpperCase().contains('S') || ref.toUpperCase().contains('W'))) {
          result = -result;
        }
        if (result != 0.0) return result;
      }

      // Fallback: parse from printable string like "[21, 1, 42.5]"
      if (printable != null && printable.isNotEmpty) {
        final parsed = parsePrintableCoordinates(printable, ref);
        if (parsed != null && parsed != 0.0) return parsed;
      }
    } catch (_) {}
    return null;
  }

  static double ratioToDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is Ratio) return val.toDouble();
    try {
      return (val as dynamic).toDouble();
    } catch (_) {}

    final str = val.toString().trim();
    if (str.contains('/')) {
      final parts = str.split('/');
      if (parts.length == 2) {
        final n = double.tryParse(parts[0].trim());
        final d = double.tryParse(parts[1].trim());
        if (n != null && d != null && d != 0) {
          return n / d;
        }
      }
    }
    return double.tryParse(str) ?? 0.0;
  }

  static double? parsePrintableCoordinates(String str, String? ref) {
    try {
      final clean = str.replaceAll('[', '').replaceAll(']', '').trim();
      final items = clean.split(',');
      if (items.isNotEmpty) {
        double deg = ratioToDouble(items[0].trim());
        double min = items.length > 1 ? ratioToDouble(items[1].trim()) : 0.0;
        double sec = items.length > 2 ? ratioToDouble(items[2].trim()) : 0.0;
        double result = deg + (min / 60.0) + (sec / 3600.0);
        if (ref != null && (ref.toUpperCase().contains('S') || ref.toUpperCase().contains('W'))) {
          result = -result;
        }
        return result;
      }
    } catch (_) {}
    return null;
  }

  /// Parse EXIF DateTime string (e.g. "2026:08:15 14:32:05")
  static DateTime? parseExifDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      final parts = dateStr.trim().split(' ');
      if (parts.length == 2) {
        final dateFormatted = parts[0].replaceAll(':', '-');
        return DateTime.parse('$dateFormatted ${parts[1]}');
      }
    } catch (_) {}
    return null;
  }

  /// Checks whether a photo waypoint name is a generic auto-generated label
  /// rather than a real place name.
  static bool isGenericPhotoName(String rawName) {
    final lower = rawName.trim().toLowerCase();
    if (lower.isEmpty) return true;
    const genericPrefixes = [
      'ảnh chụp',
      'anh chup',
      'ảnh khám phá',
      'toạ độ',
      'tọa độ',
      'img_',
      'pxl_',
      'dsc_',
      'dcim',
      'screenshot',
      'photo ',
      'image ',
    ];
    for (final prefix in genericPrefixes) {
      if (lower.startsWith(prefix)) return true;
    }
    return false;
  }

  static String normalizePlaceName(String rawName) {
    return rawName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Groups photo waypoints into folders when they share the same place name
  /// OR have nearby coordinates (same place within [proximityRadiusMeters]).
  static List<PhotoFolderCluster> groupPhotosIntoFolders(
    List<Waypoint> photos, {
    double proximityRadiusMeters = 250.0,
  }) {
    if (photos.isEmpty) return const [];

    final sorted = List<Waypoint>.from(photos)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final builders = <_PhotoFolderBuilder>[];

    for (final wp in sorted) {
      final hasPlaceName = !isGenericPhotoName(wp.name);
      final normName = hasPlaceName ? normalizePlaceName(wp.name) : null;

      final matchedIndices = <int>[];
      for (int i = 0; i < builders.length; i++) {
        final b = builders[i];
        final sameName = normName != null && b.normalizedNames.contains(normName);
        final nearby = NearbyPlacesService.distanceBetweenMeters(
              wp.latitude,
              wp.longitude,
              b.centerLat,
              b.centerLng,
            ) <=
            proximityRadiusMeters;

        if (sameName || nearby) {
          matchedIndices.add(i);
        }
      }

      if (matchedIndices.isEmpty) {
        final builder = _PhotoFolderBuilder();
        builder.addWaypoint(wp, normName);
        builders.add(builder);
      } else {
        final primary = builders[matchedIndices.first];
        primary.addWaypoint(wp, normName);
        // Merge any secondary clusters bridged by this photo
        for (int j = matchedIndices.length - 1; j >= 1; j--) {
          final other = builders.removeAt(matchedIndices[j]);
          primary.mergeFrom(other);
        }
      }
    }

    final clusters = builders.map((b) => b.build()).toList()
      ..sort((a, b) => b.latestTimestamp.compareTo(a.latestTimestamp));
    return clusters;
  }
}

class _PhotoFolderBuilder {
  final List<Waypoint> items = [];
  final Set<String> normalizedNames = {};
  final Map<String, int> displayNameCounts = {};
  double sumLat = 0.0;
  double sumLng = 0.0;

  double get centerLat => items.isEmpty ? 0.0 : sumLat / items.length;
  double get centerLng => items.isEmpty ? 0.0 : sumLng / items.length;

  void addWaypoint(Waypoint wp, String? normName) {
    items.add(wp);
    sumLat += wp.latitude;
    sumLng += wp.longitude;
    if (normName != null && normName.isNotEmpty) {
      normalizedNames.add(normName);
      final cleanDisplay = wp.name.trim();
      displayNameCounts[cleanDisplay] =
          (displayNameCounts[cleanDisplay] ?? 0) + 1;
    }
  }

  void mergeFrom(_PhotoFolderBuilder other) {
    items.addAll(other.items);
    sumLat += other.sumLat;
    sumLng += other.sumLng;
    normalizedNames.addAll(other.normalizedNames);
    other.displayNameCounts.forEach((key, count) {
      displayNameCounts[key] = (displayNameCounts[key] ?? 0) + count;
    });
  }

  PhotoFolderCluster build() {
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final cLat = centerLat;
    final cLng = centerLng;
    final first = items.first;
    final province = VietnamProvinces.matchProvince(
      cLat,
      cLng,
      '${first.name} ${first.note ?? ''}',
    );

    String folderTitle;
    if (displayNameCounts.isNotEmpty) {
      final sortedNames = displayNameCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      folderTitle = sortedNames.first.key;
    } else {
      folderTitle =
          'Điểm chụp tại $province (${cLat.toStringAsFixed(3)}, ${cLng.toStringAsFixed(3)})';
    }

    return PhotoFolderCluster(
      id: first.id,
      title: folderTitle,
      province: province,
      centerLat: cLat,
      centerLng: cLng,
      photos: List.unmodifiable(items),
      latestTimestamp: first.timestamp,
    );
  }
}
