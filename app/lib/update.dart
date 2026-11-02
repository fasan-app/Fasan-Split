// Fasan Split – updates inside the app (Nutzer 02.11.): asks GitHub Releases for the newest test version, downloads the
// APK, checks its SHA-256 (digest from the GitHub API) and hands it to the Android installer (ota_update, MIT). The user
// confirms every install. The check talks to api.github.com only: at most once a day when enabled, or on tap. MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({required this.run, required this.name, required this.url, required this.sha256, required this.size});

  /// CI run number N of version 0.1.N (build number = 100 + N, see .github/workflows/android.yml).
  final int run;
  final String name;
  final String url;
  final String? sha256;
  final int size;
}

class Updates {
  Updates._();

  static const _api = 'https://api.github.com/repos/fasan-app/Fasan-Split/releases/tags/neueste';

  /// This app's CI run number, from the build number (100 + run); null in debug builds without one.
  static Future<int?> currentRun() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final b = int.tryParse(info.buildNumber);
      return b == null || b < 100 ? null : b - 100;
    } catch (_) {
      return null; // tests, platforms without the plugin
    }
  }

  static Future<String> currentVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '?';
    }
  }

  /// Newest release, or null when there is none / no network. Throws nothing.
  static Future<UpdateInfo?> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_api));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'fasan-split');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final name = j['name'] as String? ?? '';
      final run = int.tryParse(RegExp(r'0\.1\.(\d+)').firstMatch(name)?.group(1) ?? '');
      final asset = (j['assets'] as List?)?.cast<Map<String, dynamic>>().where((a) => (a['name'] as String? ?? '').endsWith('.apk')).firstOrNull;
      if (run == null || asset == null) return null;
      final digest = asset['digest'] as String?;
      return UpdateInfo(
        run: run,
        name: name,
        url: asset['browser_download_url'] as String,
        sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7) : null,
        size: (asset['size'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Newer than the installed one?
  static Future<UpdateInfo?> available() async {
    final cur = await currentRun();
    if (cur == null) return null; // debug builds without a CI build number never ask
    final u = await latest();
    if (u == null) return null;
    return u.run > cur ? u : null;
  }

  /// Download, verify the checksum and start the Android installer. Events: progress in percent, then installing.
  static Stream<OtaEvent> install(UpdateInfo u) =>
      OtaUpdate().execute(u.url, destinationFilename: 'fasan-split.apk', sha256checksum: u.sha256);
}
