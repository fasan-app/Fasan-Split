// SPDX-License-Identifier: MPL-2.0
// Fasan Split – updates inside the app (Nutzer 02.11.): asks GitHub Releases for the newest test version, downloads the
// APK, checks its SHA-256 (digest from the GitHub API) and hands it to the Android installer (ota_update, MIT). The user
// confirms every install. The check talks to api.github.com only: at most once a day when enabled, or on tap. MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({required this.run, required this.name, required this.url, required this.sha256, required this.size, this.body = '', this.ownRun});

  /// Release text written by the CI (android.yml): commit list for developers plus the curated news per language
  /// (`<!--news:de-->…<!--/news:de-->`, from news/*.md in the repo). The app only reads the news blocks.
  final String body;

  /// CI run number of the installed app (null in debug builds): only news newer than this are shown.
  final int? ownRun;

  /// Short, plain-language news in [lang] (fallback English) that this build does not have yet, newest first.
  List<String> news(String lang) => Updates.newsSince(body, lang, ownRun);

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
        body: j['body'] as String? ?? '',
        ownRun: await currentRun(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Public page with details, change history and roadmap (Nutzer 08.11.: link instead of commit lines).
  static final repoUrl = Uri.parse('https://github.com/fasan-app/Fasan-Split');

  /// The news block of [lang] inside the release text, falling back to English; empty when there is none.
  static String newsBlock(String body, String lang) {
    for (final code in [lang, 'en']) {
      final m = RegExp('<!--news:$code-->(.*?)<!--/news:$code-->', dotAll: true).firstMatch(body);
      if (m != null) return m[1]!.trim();
    }
    return '';
  }

  /// Sections „## 0.1.N“ with „- item“ lines (format of the news files, see news/README.md): items of every section whose run is newer than
  /// [ownRun] (all when null), newest section first, at most [max] lines.
  static List<String> newsSince(String body, String lang, int? ownRun, {int max = 8}) {
    final out = <String>[];
    int? run;
    for (final line in newsBlock(body, lang).split('\n')) {
      final h = RegExp(r'^##\s+0\.1\.(\d+)\s*$').firstMatch(line.trim());
      if (h != null) {
        run = int.parse(h[1]!);
        continue;
      }
      final item = RegExp(r'^[-*]\s+(.+)$').firstMatch(line.trim());
      if (item == null || run == null) continue;
      if (ownRun != null && run <= ownRun) continue;
      out.add(item[1]!.trim());
      if (out.length >= max) break;
    }
    return out;
  }

  /// Whole news file as sections: ("0.1.84", ["item", …]), newest first, at most [maxSections].
  static List<(String, List<String>)> newsSections(String text, {int maxSections = 6}) {
    final out = <(String, List<String>)>[];
    for (final line in text.split('\n')) {
      final h = RegExp(r'^##\s+(0\.1\.\d+)\s*$').firstMatch(line.trim());
      if (h != null) {
        if (out.length >= maxSections) break;
        out.add((h[1]!, <String>[]));
        continue;
      }
      final item = RegExp(r'^[-*]\s+(.+)$').firstMatch(line.trim());
      if (item != null && out.isNotEmpty) out.last.$2.add(item[1]!.trim());
    }
    return out;
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
