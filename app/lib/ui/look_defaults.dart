// SPDX-License-Identifier: MPL-2.0
// Fasan Split – default look without costly effects (Nutzer 08.11.). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';

/// Everything that costs computing power and has no real function is off: moving colour field, grain, light band, tilt light,
/// layered shadows and the glass blur (opaque surfaces instead). Style, accent and font stay. Switchable again in Erscheinungsbild.
FasanSettings withoutCostlyEffects(FasanSettings s) => s.copyWith(
      reduceTransparency: true,
      effects: s.effects.copyWith(enabled: false, grain: 0, gradient: false, lightSweep: false, tilt: false, shadows: false),
    );
