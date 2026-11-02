// Fasan Split – a draft opens on the step it was left on, with the earlier steps underneath. MPL-2.0
import 'package:flutter/material.dart';

import '../model/bill.dart';
import 'assign.dart';
import 'flow.dart';

/// Screen of the step a draft was left on.
Widget resumeScreen(Bill b) => _stepScreen(b, b.step);

Widget _stepScreen(Bill b, int s) => switch (s) {
      2 => PeopleScreen(bill: b),
      3 => AssignScreen(bill: b),
      4 => PayScreen(bill: b),
      _ => ReviewScreen(bill: b),
    };

/// A resumed draft opens on its last step, but with the earlier steps underneath, so „zurück“ leads to the previous
/// step and not straight home (Nutzer 02.11.: angefangene Bons ließen sich teilweise nicht zurück bearbeiten – cause:
/// only the last step was pushed). A nested Navigator holds steps 1…n; when it has nothing left, back closes the bill.
class ResumeFlow extends StatefulWidget {
  const ResumeFlow({super.key, required this.bill});

  final Bill bill;

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
          for (var s = 1; s <= step; s++) MaterialPageRoute<void>(builder: (_) => _stepScreen(b, s)),
        ],
        onGenerateRoute: (_) => null,
      ),
    );
  }

}
