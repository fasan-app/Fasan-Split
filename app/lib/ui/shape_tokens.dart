// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the two corner radii of the app (Nutzer 09.11. 18:44: frames had different roundings). A card, a bill, a group
// frame, a banner use [rCard]; things inside a card (item rows, chips on a surface, notes) use [rInner]. Never `radius * 0.6/0.8`.
import 'package:fasan_ui/fasan_ui.dart';

extension FasanShapes on FasanLook {
  /// Outer shape: cards, bill rows, frames, banners, sheets' inner blocks.
  double get rCard => radius * 0.7;

  /// Inner shape: rows inside a card, notes, small surfaces.
  double get rInner => radius * 0.5;
}

/// Vertical rhythm of the lists (Nutzer 09.11. 18:44: Abstände ungleichmäßig): the gap between two rows is always [kRowGap];
/// a heading has [kHeadingTop] above and [FasanSpace.s] below. Same in bills, items and the trash.
const double kRowGap = FasanSpace.s;
const double kHeadingTop = FasanSpace.l;
