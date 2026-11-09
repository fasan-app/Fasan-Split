// SPDX-License-Identifier: MPL-2.0
// Fasan Split – a draft opens on the step it was left on, with the earlier steps underneath. MPL-2.0
import 'package:flutter/material.dart';

import 'package:fasan_core/bill.dart';
import 'flow.dart';

/// Screen of the step a draft was left on.
Widget resumeScreen(Bill b) => _stepScreen(b, b.step);

/// Since 05.11. there are two screens: the bill (old steps 1–3) and the summary (step 4). Drafts saved on step 2 or 3 open the bill.
Widget _stepScreen(Bill b, int s, {int? focusItem}) => switch (s) {
      4 => PayScreen(bill: b),
      _ => ReviewScreen(bill: b, focusItem: focusItem),
    };

/// A resumed draft opens on its last step, but with the earlier steps underneath, so „zurück“ leads to the previous
/// step and not straight home (Nutzer 02.11.: angefangene Bons ließen sich teilweise nicht zurück bearbeiten – cause:
/// only the last step was pushed). A nested Navigator holds steps 1…n; when it has nothing left, back closes the bill.
class ResumeFlow extends StatefulWidget {
  const ResumeFlow({super.key, required this.bill, this.focusItem});

  final Bill bill;
  final int? focusItem; // item to lead the eye to, see ReviewScreen

  @override
  State<ResumeFlow> createState() => _ResumeFlowState();
}

class _ResumeFlowState extends State<ResumeFlow> {
  final _nav = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final step = b.step.clamp(1, 4);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final n = _nav.currentState;
        if (n != null && n.canPop()) {
          n.pop();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Navigator(
        key: _nav,
        onGenerateInitialRoutes: (_, _) => [
          // the summary sits on top of the bill, so „back“ from it leads to the bill
          for (final s in step >= 4 ? const [1, 4] : const [1]) MaterialPageRoute<void>(builder: (_) => _stepScreen(b, s, focusItem: s == 1 ? widget.focusItem : null)),
        ],
        onGenerateRoute: (_) => null,
      ),
    );
  }

}
