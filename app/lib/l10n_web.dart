// Fasan Split – texts of the web app (browser). German and English, Du-Form, short sentences. MPL-2.0
import 'l10n.dart';

extension WebTexts on S {
  String get webHint => de
      ? 'Du nutzt Fasan Split im Browser. Hier geht alles wie in der App.'
      : 'You are using Fasan Split in the browser. Everything works here like in the app.';
  String get webOpenApp => de ? 'In der App öffnen' : 'Open in the app';
  String get webGetApp => de ? 'App für Android laden' : 'Get the Android app';
}
