import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/map_settings_provider.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

class AppUpdateDialog {
  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Checks GitHub Releases for a newer version and prompts the user to
  /// download & install the APK automatically when an update is available.
  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool silentIfUpToDate = false,
  }) async {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);

    if (!silentIfUpToDate) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            content: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.8),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Đang kiểm tra phiên bản mới trên GitHub...',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final result = await AppUpdateService().checkForUpdate(
      githubToken: settings.githubUpdateToken,
    );

    if (!context.mounted) return;
    if (!silentIfUpToDate) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!result.success) {
      if (silentIfUpToDate) return;
      if (result.requiresAuth) {
        await _showPrivateRepoTokenDialog(context, result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Không thể kiểm tra cập nhật.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (!result.hasUpdate) {
      if (silentIfUpToDate) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green, size: 26),
              SizedBox(width: 8),
              Expanded(child: Text('Đã là bản mới nhất!')),
            ],
          ),
          content: Text(
            'Bạn đang sử dụng phiên bản mới nhất (${result.currentVersion.displayVersion}).',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }

    // Newer version found -> ask user to download & install!
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateAvailablePromptDialog(
        updateInfo: result,
        githubToken: settings.githubUpdateToken,
      ),
    );
  }

  static Future<void> _showPrivateRepoTokenDialog(
    BuildContext context,
    AppUpdateCheckResult result,
  ) async {
    final settings = Provider.of<MapSettingsProvider>(context, listen: false);
    final controller = TextEditingController(text: settings.githubUpdateToken);

    final shouldRecheck = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Kho cập nhật Riêng tư',
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
              Text(
                result.errorMessage ??
                    'Kho GitHub đang ở chế độ Riêng tư (Private). Nhập GitHub Personal Access Token (quyền Contents: Read-only) một lần duy nhất để tự động kiểm tra và tải APK.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub Token (ghp_... / github_pat_...)',
                  hintText: 'Dán token quyền Read-only Contents',
                  prefixIcon: Icon(Icons.key_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Lưu & Kiểm tra lại'),
            onPressed: () async {
              await settings.setGithubUpdateToken(controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
    );

    controller.dispose();
    if (shouldRecheck == true && context.mounted) {
      await checkAndPrompt(context);
    }
  }
}

class _UpdateAvailablePromptDialog extends StatefulWidget {
  final AppUpdateCheckResult updateInfo;
  final String githubToken;

  const _UpdateAvailablePromptDialog({
    required this.updateInfo,
    required this.githubToken,
  });

  @override
  State<_UpdateAvailablePromptDialog> createState() => _UpdateAvailablePromptDialogState();
}

class _UpdateAvailablePromptDialogState extends State<_UpdateAvailablePromptDialog> {
  bool _isDownloading = false;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedFilePath;
  String? _statusNote;
  String? _errorText;
  AppUpdateCancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownloadAndInstall() async {
    if (!widget.updateInfo.hasApkAsset) {
      final htmlUrl = widget.updateInfo.releaseHtmlUrl;
      if (htmlUrl != null && htmlUrl.isNotEmpty) {
        await launchUrl(Uri.parse(htmlUrl), mode: LaunchMode.externalApplication);
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    final token = AppUpdateCancelToken();
    setState(() {
      _isDownloading = true;
      _receivedBytes = 0;
      _totalBytes = widget.updateInfo.assetSizeBytes;
      _errorText = null;
      _statusNote = null;
      _cancelToken = token;
    });

    try {
      final File apkFile = await AppUpdateService().downloadReleaseApk(
        updateInfo: widget.updateInfo,
        githubToken: widget.githubToken,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            if (total > 0) _totalBytes = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadedFilePath = apkFile.path;
      });

      await _triggerInstall(apkFile.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _triggerInstall(String filePath) async {
    final status = await AppUpdateService().installApk(filePath);
    if (!mounted) return;

    if (status == ApkInstallStatus.needsPermission) {
      setState(() {
        _statusNote =
            'Hãy bật công tắc "Cho phép từ nguồn này" trên màn hình cài đặt vừa mở. Khi quay lại, ứng dụng sẽ tự động mở trình cập nhật (hoặc bấm "Cài đặt ngay" bên dưới).';
      });
    } else if (status == ApkInstallStatus.installerLaunched) {
      setState(() {
        _statusNote =
            'Đã tải xong! Hộp thoại cài đặt hệ thống đang mở — hãy chọn "Cập nhật" để hoàn tất.';
      });
    } else {
      setState(() {
        _errorText = 'Không thể gọi trình cài đặt gói Android.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;
    final progress = (_totalBytes > 0 && _receivedBytes > 0)
        ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0)
        : null;
    final sizeLabel = AppUpdateDialog._formatSize(
      _totalBytes > 0 ? _totalBytes : info.assetSizeBytes,
    );

    return PopScope(
      canPop: !_isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Có bản cập nhật mới!',
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.releaseName ?? info.latestVersion?.displayVersion ?? 'Phiên bản mới',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hiện tại: ${info.currentVersion.displayVersion}  →  Mới: ${info.latestVersion?.displayVersion ?? ''}'
                      '${sizeLabel.isNotEmpty ? ' ($sizeLabel)' : ''}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Nội dung cập nhật:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      info.releaseNotes!,
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(6),
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  progress != null
                      ? 'Đang tải về: ${(progress * 100).toStringAsFixed(0)}% (${AppUpdateDialog._formatSize(_receivedBytes)} / $sizeLabel)'
                      : 'Đang tải về: ${AppUpdateDialog._formatSize(_receivedBytes)}...',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              if (_statusNote != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _statusNote!,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              ],
              if (!_isDownloading && _downloadedFilePath == null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Bạn có muốn tải bản cập nhật mới về và tiến hành cập nhật ngay không?',
                  style: TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_isDownloading)
            TextButton(
              onPressed: () {
                _cancelToken?.cancel();
              },
              child: const Text('Huỷ tải', style: TextStyle(color: Colors.redAccent)),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_downloadedFilePath != null ? 'Đóng' : 'Để sau'),
            ),
            if (_downloadedFilePath != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                icon: const Icon(Icons.install_mobile_rounded, size: 18),
                label: const Text('Cài đặt ngay'),
                onPressed: () => _triggerInstall(_downloadedFilePath!),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Tải về & Cập nhật'),
                onPressed: _startDownloadAndInstall,
              ),
          ],
        ],
      ),
    );
  }
}
