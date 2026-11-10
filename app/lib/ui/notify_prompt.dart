// SPDX-License-Identifier: MPL-2.0
// Fasan Split – asks once, in context, whether this device may show notifications (Nutzer 09.11.: essential, switchable in the
// settings). Asked right after the user agreed to share (a fresh tap, which the browser needs for its permission question), not at
// the first start. MPL-2.0
import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import 'scope.dart';

/// Asks once. Does nothing without a device notifier (tests), when already on, or when it was asked before.
Future<void> askNotificationsOnce(BuildContext context) async {
  final n = deviceNotifier;
  if (n == null || n.enabled || n.asked) return;
  await n.markAsked();
  if (!context.mounted) return;
  final on = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('notify.askTitle')),
      content: Text(ctx.tr('notify.askBody')),
      actions: [
        TextButton(key: const ValueKey('notify-later'), onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('notify.askLater'))),
        FilledButton(key: const ValueKey('notify-on'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('notify.askOn'))),
      ],
    ),
  );
  if (on != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final blocked = context.tr('notify.askBlocked');
  if (!await n.setEnabled(true)) messenger.showSnackBar(SnackBar(content: Text(blocked)));
}
