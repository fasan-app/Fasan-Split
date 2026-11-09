// SPDX-License-Identifier: MPL-2.0
// Fasan Split – text lookup by key. No text of the app is written in the code: `context.tr('bill.done')` finds it in the table of
// the current language (strings_<code>.dart). {0}, {1}… in a text are filled from the arguments. MPL-2.0
import 'package:flutter/widgets.dart';

import 'languages.dart';

/// [key] in [lang] (a language code), then English, then German, else the key itself (visible in tests and screens, never empty).
String trLang(String lang, String key, [List<Object?> args = const []]) {
  final l = languageFor(lang);
  final text = l.strings[key] ?? languageFor('en').strings[key] ?? appLanguages.first.strings[key] ?? key;
  if (args.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
    final i = int.parse(m[1]!);
    return i < args.length ? '${args[i]}' : m[0]!;
  });
}

/// Plural: `key.one` for one, `key.other` otherwise (per language rule); {0} is the number unless [args] are given.
String trnLang(String lang, String key, int n, [List<Object?>? args]) {
  final l = languageFor(lang);
  return trLang(lang, '$key.${l.pluralOne(n) ? 'one' : 'other'}', args ?? [n]);
}

extension AppTexts on BuildContext {
  /// Language code the app shows right now (the language setting, or the phone's language when it is one of ours, else English).
  String get langCode {
    final code = Localizations.maybeLocaleOf(this)?.languageCode;
    return languageFor(code).code;
  }

  String tr(String key, [List<Object?> args = const []]) => trLang(langCode, key, args);

  String trn(String key, int n, [List<Object?>? args]) => trnLang(langCode, key, n, args);
}
