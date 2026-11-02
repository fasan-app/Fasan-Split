// Fasan Split – update banner and install sheet (lib/update.dart). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../l10n.dart';
import '../update.dart';

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
          TextButton(onPressed: () => showUpdateSheet(context, info), child: Text(t.install)),
          IconButton(tooltip: t.close, onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
  }
}

/// Download with progress, checksum, then the Android installer.
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) => showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      builder: (context) => _UpdateSheet(info: info),
    );

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  late final Stream<OtaEvent> _events = Updates.install(widget.info);

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FasanSpace.l),
        child: StreamBuilder<OtaEvent>(
          stream: _events,
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
