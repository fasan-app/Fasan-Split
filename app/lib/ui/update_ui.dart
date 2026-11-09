// SPDX-License-Identifier: MPL-2.0
// Fasan Split – update banner and install sheet (lib/update.dart). MPL-2.0
import '../l10n/tr.dart' show trLang, AppTexts;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../flows/update.dart';
import '../platform/web_platform.dart';

/// Banner on the start page when a newer version exists.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.info, required this.onClose});

  final UpdateInfo info;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    return Material(
      color: l.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(l.radius * 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.s, FasanSpace.xs, FasanSpace.s),
        child: Row(children: [
          Icon(Icons.system_update_rounded, color: l.accent),
          const SizedBox(width: FasanSpace.m),
          Expanded(child: Text(t.updateAvailable(info.name), style: Theme.of(context).textTheme.bodyMedium)),
          TextButton(onPressed: () => showUpdateSheet(context, info), child: Text(t.showUpdate)),
          IconButton(tooltip: t.close, onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
  }
}

/// Browser: a newer web build is on the server. Loading the page again is the whole update.
class WebUpdateBanner extends StatelessWidget {
  const WebUpdateBanner({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    return Material(
      color: l.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(l.radius * 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.s, FasanSpace.xs, FasanSpace.s),
        child: Row(children: [
          Icon(Icons.refresh_rounded, color: l.accent),
          const SizedBox(width: FasanSpace.m),
          Expanded(child: Text(trLang(t.de ? 'de' : 'en', 'update_ui.newVersionAvailableReload'), style: Theme.of(context).textTheme.bodyMedium)),
          TextButton(onPressed: reloadPage, child: Text(trLang(t.de ? 'de' : 'en', 'update_ui.reload'))),
          IconButton(tooltip: t.close, onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
  }
}

/// First size and change list, nothing is downloaded (Nutzer 02.11.); on „Laden und installieren“: download with
/// progress, checksum, then the Android installer.
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UpdateSheet(info: info),
    );

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  Stream<OtaEvent>? _events;

  Widget _preview(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final i = widget.info;
    final news = i.news(context.langCode);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FasanSpace.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(i.name, style: tt.titleMedium),
          const SizedBox(height: FasanSpace.xs),
          Text(t.updateSize((i.size / 1048576).round()), style: tt.bodySmall),
          const SizedBox(height: FasanSpace.m),
          FasanLabel(t.updateChanges),
          const SizedBox(height: FasanSpace.xs),
          if (news.isEmpty)
            // never an empty window: a build without its own news entry still says something (Nutzer 08.11. 11:09)
            Text(t.updateNoNews, style: tt.bodyMedium)
          else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(shrinkWrap: true, children: [
                for (final c in news)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $c', style: tt.bodyMedium)),
              ]),
            ),
          ],
          // details, history and roadmap live in the public repository (Nutzer 08.11.)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('update-repo-link'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(t.updateRepoLink),
              onPressed: () => launchUrl(Updates.repoUrl, mode: LaunchMode.externalApplication),
            ),
          ),
          const SizedBox(height: FasanSpace.m),
          Text(t.updateWhole, style: tt.bodySmall),
          const SizedBox(height: FasanSpace.m),
          Row(children: [
            FasanButton(label: t.later, kind: FasanButtonKind.secondary, onPressed: () => Navigator.pop(context)),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: FasanButton(label: t.updateLoad, icon: Icons.download_rounded, expand: true, onPressed: () => setState(() => _events = Updates.install(i)))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final events = _events;
    if (events == null) return _preview(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FasanSpace.l),
        child: StreamBuilder<OtaEvent>(
          stream: events,
          builder: (context, snap) {
            final e = snap.data;
            final error = snap.hasError || (e != null && e.status != OtaStatus.DOWNLOADING && e.status != OtaStatus.INSTALLING && e.status != OtaStatus.INSTALLATION_DONE);
            final pct = e?.status == OtaStatus.DOWNLOADING ? (double.tryParse(e?.value ?? '') ?? 0) / 100 : null;
            final text = error
                ? t.updateError([e?.status.name ?? '${snap.error}', if ((e?.value ?? '').isNotEmpty) e!.value!].join(': '))
                : switch (e?.status) {
                    OtaStatus.INSTALLING => t.updateInstalling,
                    OtaStatus.INSTALLATION_DONE => t.updateDone,
                    _ => t.updateDownloading((widget.info.size / 1048576).round()),
                  };
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.info.name, style: tt.titleMedium),
              const SizedBox(height: FasanSpace.m),
              Text(text, style: tt.bodyMedium),
              const SizedBox(height: FasanSpace.m),
              if (!error) LinearProgressIndicator(value: pct),
              const SizedBox(height: FasanSpace.m),
              Text(t.updateNote, style: tt.bodySmall),
              const SizedBox(height: FasanSpace.m),
              // the in-app download can fail on some phones/networks: the browser downloads the same file and Android installs it
              if (error) ...[
                FasanButton(
                    key: const ValueKey('update-browser'),
                    label: t.updateBrowser,
                    icon: Icons.open_in_new_rounded,
                    expand: true,
                    onPressed: () => launchUrl(Uri.parse(widget.info.url), mode: LaunchMode.externalApplication)),
                const SizedBox(height: FasanSpace.s),
              ],
              FasanButton(label: t.close, kind: FasanButtonKind.secondary, expand: true, onPressed: () => Navigator.pop(context)),
            ]);
          },
        ),
      ),
    );
  }
}
