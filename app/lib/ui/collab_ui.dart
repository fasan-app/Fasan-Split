// SPDX-License-Identifier: MPL-2.0
// Fasan Split – screens of the collaboration. Split by area (13.11., Umbau): the parts live in collab_*.dart; this file only
// exports them so existing imports keep working. Public relays are contacted only after the user has agreed in the consent
// dialog, and tests never reach them (they use MemoryRelay). MPL-2.0
export 'collab_dialogs.dart';
export 'collab_invite.dart';
export 'collab_notes.dart';
export 'collab_chat.dart';
export 'collab_panel.dart';
export 'collab_account.dart';
export 'collab_activity.dart';
// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).
export 'join_screen.dart' show JoinScreen, AccountSafetyCard;
