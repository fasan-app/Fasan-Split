// Fasan Split – the bill tile grows into the bill (container transform, fasan_ui GESTALTUNG.md §7). MPL-2.0
//
// Why not FasanOpenContainer: it paints the opened page on the opaque `look.background` colour, so every bill opened from a tile
// lost the soft ground that all other screens have (Nutzer 06.11., Bildschirmvergleich: group screen with ground, bill flat).
// Pages are transparent over FasanBackdrop everywhere else, so here the open colour is transparent too.
import 'package:animations/animations.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

class BillOpenContainer extends StatelessWidget {
  const BillOpenContainer({super.key, required this.closedBuilder, required this.openBuilder, this.radius});

  /// Call `open` to start the transition.
  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;
  final WidgetBuilder openBuilder;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final m = FasanMotion.of(context);
    return OpenContainer<Object?>(
      closedColor: l.surface,
      openColor: Colors.transparent,
      middleColor: l.surface,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius ?? l.radius)),
      tappable: false,
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration: m.enabled ? const Duration(milliseconds: 420) : const Duration(milliseconds: 150),
      // During the transition the closed card is drawn in the overlay, outside the page's Material: give ink a surface.
      closedBuilder: (context, open) => Material(type: MaterialType.transparency, child: closedBuilder(context, open)),
      openBuilder: (context, _) => openBuilder(context),
    );
  }
}
