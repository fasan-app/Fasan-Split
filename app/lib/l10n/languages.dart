// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the list of app languages. To add a language: (1) copy `strings_en.dart`, `tips_en.dart` and `tutorial_en.dart` to `…_<code>.dart`, translate the
// values (keys and {0} placeholders stay), (2) add one line here. Nothing else in the code changes. See docs/SPRACHEN.md. MPL-2.0
import 'strings_de.dart';
import 'strings_en.dart';
import 'tips_de.dart';
import 'tips_en.dart';
import 'tutorial_de.dart';
import 'tutorial_en.dart';

class AppLanguage {
  const AppLanguage(this.code, this.name, this.strings, {this.pluralOne = _oneIfOne});

  /// ISO 639-1 code, also the Flutter locale's language code.
  final String code;

  /// Name in the language itself (shown in the language list).
  final String name;
  final Map<String, String> strings;

  /// Whether [n] takes the „one“ form of a plural key (`key.one` / `key.other`). Languages with more forms add their own rule.
  final bool Function(int n) pluralOne;
}

bool _oneIfOne(int n) => n == 1;

/// All languages. The first one is the fallback when a key is missing in a language and in English.
const appLanguages = <AppLanguage>[
  AppLanguage('de', 'Deutsch', {...stringsDe, ...tipsDe, ...tutorialDe}),
  AppLanguage('en', 'English', {...stringsEn, ...tipsEn, ...tutorialEn}),
];

/// The language for a language code (`de`, `en`, …); English for an unknown one.
AppLanguage languageFor(String? code) => appLanguages.firstWhere((l) => l.code == code, orElse: () => appLanguages.firstWhere((l) => l.code == 'en'));
