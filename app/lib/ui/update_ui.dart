// Fasan Split – update banner and install sheet (lib/update.dart). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

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
          Expanded(child: Text(t.de ? 'Neue Version da. Lade die Seite neu.' : 'New version available. Reload the page.', style: Theme.of(context).textTheme.bodyMedium)),
          TextButton(onPressed: reloadPage, child: Text(t.de ? 'Neu laden' : 'Reload')),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FasanSpace.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(i.name, style: tt.titleMedium),
          const SizedBox(height: FasanSpace.xs),
          Text(t.updateSize((i.size / 1048576).round()), style: tt.bodySmall),
          if (i.changes.isNotEmpty) ...[
            const SizedBox(height: FasanSpace.m),
            FasanLabel(t.updateChanges),
            const SizedBox(height: FasanSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(shrinkWrap: true, children: [
                for (final c in i.changes)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $c', style: tt.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],
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
                ? t.updateError('${e?.status.name ?? snap.error}')
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
              FasanButton(label: t.close, kind: FasanButtonKind.secondary, expand: true, onPressed: () => Navigator.pop(context)),
            ]);
          },
        ),
      ),
    );
  }
}
