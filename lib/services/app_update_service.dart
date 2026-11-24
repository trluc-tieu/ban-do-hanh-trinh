import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppVersionInfo implements Comparable<AppVersionInfo> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const AppVersionInfo({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
  });

  String get displayVersion => 'v$major.$minor.$patch';

  String get fullDisplay => build > 0 ? 'v$major.$minor.$patch+$build' : displayVersion;

  static AppVersionInfo? tryParse(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1).trim();
    }

    int buildNum = 0;
    final plusIdx = cleaned.indexOf('+');
    if (plusIdx >= 0) {
      buildNum = int.tryParse(cleaned.substring(plusIdx + 1).trim()) ?? 0;
      cleaned = cleaned.substring(0, plusIdx);
    }

    final dashIdx = cleaned.indexOf('-');
    if (dashIdx >= 0) {
      cleaned = cleaned.substring(0, dashIdx);
    }

    final parts = cleaned.split('.');
    if (parts.isEmpty) return null;
    final major = int.tryParse(parts[0]);
    if (major == null) return null;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final patch = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

    return AppVersionInfo(
      major: major,
      minor: minor,
      patch: patch,
      build: buildNum,
    );
  }

  @override
  int compareTo(AppVersionInfo other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (build > 0 && other.build > 0 && build != other.build) {
      return build.compareTo(other.build);
    }
    return 0;
  }

  bool operator >(AppVersionInfo other) => compareTo(other) > 0;

  @override
  String toString() => '$major.$minor.$patch${build > 0 ? '+$build' : ''}';
}

class AppUpdateCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class AppUpdateCheckResult {
  final bool success;
  final bool hasUpdate;
  final AppVersionInfo currentVersion;
  final AppVersionInfo? latestVersion;
  final String? releaseName;
  final String? releaseNotes;
  final String? browserDownloadUrl;
  final String? apiAssetUrl;
  final String? assetName;
  final int assetSizeBytes;
  final String? releaseHtmlUrl;
  final bool requiresAuth;
  final String? errorMessage;

  const AppUpdateCheckResult({
    required this.success,
    required this.hasUpdate,
    required this.currentVersion,
    this.latestVersion,
    this.releaseName,
    this.releaseNotes,
    this.browserDownloadUrl,
    this.apiAssetUrl,
    this.assetName,
    this.assetSizeBytes = 0,
    this.releaseHtmlUrl,
    this.requiresAuth = false,
    this.errorMessage,
  });

  bool get hasApkAsset =>
      (browserDownloadUrl != null && browserDownloadUrl!.isNotEmpty) ||
      (apiAssetUrl != null && apiAssetUrl!.isNotEmpty);
}

enum ApkInstallStatus {
  installerLaunched,
  needsPermission,
  failed,
}

class AppUpdateService {
  static const String repoOwner = 'trluc-tieu';
  static const String repoName = 'ban-do-hanh-trinh';
  static const String fallbackAppVersion = '1.1.0+2';

  static const String _envGithubToken = String.fromEnvironment('GITHUB_UPDATE_TOKEN');
  static const MethodChannel _channel = MethodChannel('trluc.top/app_updater');

  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  String _effectiveToken(String? customToken) {
    final trimmed = customToken?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    return _envGithubToken.trim();
  }

  Future<AppVersionInfo> getCurrentVersion() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getAppVersion');
      if (res != null) {
        final name = (res['versionName'] as String?) ?? '1.1.0';
        final code = (res['versionCode'] as num?)?.toInt() ?? 0;
        final parsed = AppVersionInfo.tryParse('$name+$code');
        if (parsed != null) return parsed;
      }
    } catch (_) {
      // Fallback when running in widget tests or non-Android host
    }
    return AppVersionInfo.tryParse(fallbackAppVersion) ??
        const AppVersionInfo(major: 1, minor: 1, patch: 0, build: 2);
  }

  static AppUpdateCheckResult parseGithubReleaseJson(
    Map<String, dynamic> data,
    AppVersionInfo currentVersion,
  ) {
    final tagName = (data['tag_name'] as String?)?.trim() ?? '';
    if (tagName.isEmpty) {
      return AppUpdateCheckResult(
        success: false,
        hasUpdate: false,
        currentVersion: currentVersion,
        errorMessage: 'Không đọc được tag phiên bản từ GitHub.',
      );
    }

    final latest = AppVersionInfo.tryParse(tagName);
    if (latest == null) {
      return AppUpdateCheckResult(
        success: false,
        hasUpdate: false,
        currentVersion: currentVersion,
        errorMessage: 'Định dạng phiên bản không hợp lệ: $tagName',
      );
    }

    final rawAssets = (data['assets'] as List<dynamic>?) ?? const [];
    Map<String, dynamic>? chosenAsset;

    for (final item in rawAssets) {
      if (item is Map<String, dynamic>) {
        final name = (item['name'] as String?)?.toLowerCase() ?? '';
        if (name.endsWith('.apk')) {
          chosenAsset = item;
          if (name.contains('release') || name.contains('universal')) {
            break;
          }
        }
      }
    }

    final releaseTitle = (data['name'] as String?)?.trim();
    final body = (data['body'] as String?)?.trim();
    final htmlUrl = (data['html_url'] as String?)?.trim();

    return AppUpdateCheckResult(
      success: true,
      hasUpdate: latest > currentVersion,
      currentVersion: currentVersion,
      latestVersion: latest,
      releaseName: (releaseTitle != null && releaseTitle.isNotEmpty) ? releaseTitle : tagName,
      releaseNotes: body,
      browserDownloadUrl: chosenAsset?['browser_download_url'] as String?,
      apiAssetUrl: chosenAsset?['url'] as String?,
      assetName: chosenAsset?['name'] as String?,
      assetSizeBytes: (chosenAsset?['size'] as num?)?.toInt() ?? 0,
      releaseHtmlUrl: htmlUrl,
    );
  }

  Future<AppUpdateCheckResult> checkForUpdate({String? githubToken}) async {
    final current = await getCurrentVersion();
    final token = _effectiveToken(githubToken);

    final uri = Uri.parse(
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
    );

    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'BanDoHanhTrinh/${current.major}.${current.minor}.${current.patch}',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final resp = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 15),
          );

      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        return parseGithubReleaseJson(jsonMap, current);
      }

      if (resp.statusCode == 404 || resp.statusCode == 401) {
        return AppUpdateCheckResult(
          success: false,
          hasUpdate: false,
          currentVersion: current,
          requiresAuth: true,
          errorMessage: token.isEmpty
              ? 'Kho GitHub ($repoOwner/$repoName) đang ở chế độ Riêng tư (Private). Hãy nhập GitHub Token (quyền Read Contents) để kiểm tra & tải bản cập nhật tự động.'
              : 'GitHub Token không hợp lệ hoặc chưa có bản Release nào trên kho lưu trữ (HTTP ${resp.statusCode}).',
        );
      }

      return AppUpdateCheckResult(
        success: false,
        hasUpdate: false,
        currentVersion: current,
        errorMessage: 'Không thể kiểm tra cập nhật từ GitHub (HTTP ${resp.statusCode}).',
      );
    } on TimeoutException {
      return AppUpdateCheckResult(
        success: false,
        hasUpdate: false,
        currentVersion: current,
        errorMessage: 'Quá thời gian kết nối tới máy chủ GitHub. Vui lòng kiểm tra mạng.',
      );
    } catch (e) {
      return AppUpdateCheckResult(
        success: false,
        hasUpdate: false,
        currentVersion: current,
        errorMessage: 'Lỗi kết nối mạng khi kiểm tra cập nhật: $e',
      );
    }
  }

  /// Downloads the APK asset (supporting both public GitHub releases and
  /// authenticated private repository assets via GitHub REST API octet-stream).
  Future<File> downloadReleaseApk({
    required AppUpdateCheckResult updateInfo,
    String? githubToken,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    AppUpdateCancelToken? cancelToken,
  }) async {
    final token = _effectiveToken(githubToken);
    final useApiAsset = token.isNotEmpty &&
        updateInfo.apiAssetUrl != null &&
        updateInfo.apiAssetUrl!.isNotEmpty;

    final initialUrl = useApiAsset
        ? updateInfo.apiAssetUrl!
        : (updateInfo.browserDownloadUrl ?? updateInfo.apiAssetUrl);

    if (initialUrl == null || initialUrl.isEmpty) {
      throw Exception('Bản phát hành này chưa đính kèm tệp cài đặt APK.');
    }

    final tempDir = await getTemporaryDirectory();
    final updatesDir = Directory(p.join(tempDir.path, 'apk_updates'));
    if (await updatesDir.exists()) {
      await for (final entity in updatesDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } else {
      await updatesDir.create(recursive: true);
    }

    final safeName = (updateInfo.assetName != null && updateInfo.assetName!.isNotEmpty)
        ? updateInfo.assetName!.replaceAll(RegExp(r'[^\w.\-]'), '_')
        : 'BanDoHanhTrinh-${updateInfo.latestVersion?.displayVersion ?? 'latest'}.apk';
    final targetFile = File(p.join(updatesDir.path, safeName));

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      Uri downloadUri = Uri.parse(initialUrl);

      if (useApiAsset) {
        // GitHub Private Release Asset API returns a 302 redirect to a pre-signed S3 URL.
        // We MUST NOT forward the GitHub Authorization header to S3.
        final req = await client.getUrl(downloadUri);
        req.followRedirects = false;
        req.headers.set(HttpHeaders.userAgentHeader, 'BanDoHanhTrinh-Updater');
        req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

        final redirectResp = await req.close();
        if (redirectResp.isRedirect ||
            redirectResp.statusCode == 302 ||
            redirectResp.statusCode == 301 ||
            redirectResp.statusCode == 307) {
          final loc = redirectResp.headers.value(HttpHeaders.locationHeader);
          await redirectResp.drain<void>();
          if (loc == null || loc.isEmpty) {
            throw Exception('Không nhận được đường dẫn tải tệp APK từ GitHub.');
          }
          downloadUri = Uri.parse(loc);
        } else if (redirectResp.statusCode == 200) {
          return await _pipeResponseToFile(
            response: redirectResp,
            targetFile: targetFile,
            expectedBytes: updateInfo.assetSizeBytes,
            onProgress: onProgress,
            cancelToken: cancelToken,
          );
        } else {
          await redirectResp.drain<void>();
          throw Exception('Tải APK thất bại (HTTP ${redirectResp.statusCode}).');
        }
      }

      final fileReq = await client.getUrl(downloadUri);
      fileReq.headers.set(HttpHeaders.userAgentHeader, 'BanDoHanhTrinh-Updater');
      fileReq.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream, */*');
      final fileResp = await fileReq.close();

      if (fileResp.statusCode != 200) {
        await fileResp.drain<void>();
        throw Exception('Không thể tải tệp APK (HTTP ${fileResp.statusCode}).');
      }

      return await _pipeResponseToFile(
        response: fileResp,
        targetFile: targetFile,
        expectedBytes: updateInfo.assetSizeBytes,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } finally {
      client.close(force: false);
    }
  }

  Future<File> _pipeResponseToFile({
    required HttpClientResponse response,
    required File targetFile,
    required int expectedBytes,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    AppUpdateCancelToken? cancelToken,
  }) async {
    final total = response.contentLength > 0 ? response.contentLength : expectedBytes;
    final sink = targetFile.openWrite();
    int received = 0;

    try {
      await for (final chunk in response) {
        if (cancelToken?.isCancelled == true) {
          await sink.close();
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          throw Exception('Đã huỷ tải bản cập nhật.');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      return targetFile;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<ApkInstallStatus> installApk(String filePath) async {
    try {
      final status = await _channel.invokeMethod<String>(
        'installApk',
        {'filePath': filePath},
      );
      if (status == 'NEEDS_PERMISSION') {
        return ApkInstallStatus.needsPermission;
      }
      return ApkInstallStatus.installerLaunched;
    } catch (_) {
      return ApkInstallStatus.failed;
    }
  }
}
