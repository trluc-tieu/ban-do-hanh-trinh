import 'package:ban_do_hanh_trinh/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersionInfo', () {
    test('parses tags with v prefix, build and suffix', () {
      final v = AppVersionInfo.tryParse('v1.2.3+4')!;
      expect([v.major, v.minor, v.patch, v.build], [1, 2, 3, 4]);
      expect(AppVersionInfo.tryParse('2.0')!.patch, 0);
      expect(AppVersionInfo.tryParse('v1.0.0-beta')!.major, 1);
      expect(AppVersionInfo.tryParse('abc'), isNull);
    });

    test('compares versions correctly', () {
      final a = AppVersionInfo.tryParse('1.1.0+2')!;
      expect(AppVersionInfo.tryParse('v1.1.1')! > a, isTrue);
      expect(AppVersionInfo.tryParse('v1.1.0')! > a, isFalse);
      expect(AppVersionInfo.tryParse('v1.0.9')! > a, isFalse);
      expect(AppVersionInfo.tryParse('v2.0.0')! > a, isTrue);
    });
  });

  group('parseGithubReleaseJson', () {
    final current = AppVersionInfo.tryParse('1.1.0+2')!;

    test('detects newer release and picks the APK asset', () {
      final res = AppUpdateService.parseGithubReleaseJson({
        'tag_name': 'v1.2.0',
        'name': 'Bản 1.2.0',
        'body': 'Ghi chú',
        'html_url': 'https://github.com/x/y/releases/tag/v1.2.0',
        'assets': [
          {'name': 'notes.txt', 'url': 'u0', 'browser_download_url': 'b0', 'size': 1},
          {'name': 'app-release.apk', 'url': 'u1', 'browser_download_url': 'b1', 'size': 1234},
        ],
      }, current);
      expect(res.success, isTrue);
      expect(res.hasUpdate, isTrue);
      expect(res.assetName, 'app-release.apk');
      expect(res.apiAssetUrl, 'u1');
      expect(res.assetSizeBytes, 1234);
    });

    test('same version means no update', () {
      final res = AppUpdateService.parseGithubReleaseJson({
        'tag_name': 'v1.1.0',
        'assets': [],
      }, current);
      expect(res.success, isTrue);
      expect(res.hasUpdate, isFalse);
      expect(res.hasApkAsset, isFalse);
    });

    test('invalid tag fails gracefully', () {
      final res = AppUpdateService.parseGithubReleaseJson({'tag_name': ''}, current);
      expect(res.success, isFalse);
    });
  });
}
