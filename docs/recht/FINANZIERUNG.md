# Finanzierung und Veröffentlichungsmodell

Stand 08.11.2026. Frage des Nutzers (08.11.): Eine kostenlose und eine bezahlte Version mit Premium-Funktionen, um Arbeit und Aufwand auszugleichen,
**oder** alles öffentlich machen und um Spenden bitten – was ist der bessere Weg für die Community? Vertrauensmarken siehe [README](README.md).

## Kurzfassung

- **Empfehlung** [wahrscheinlich]: **Alles offen (MPL-2.0), die App für alle Funktionen kostenlos, ohne Werbung und ohne Sperre – dazu eine leise Spendenbitte.** Später optional **bezahlte Dienste**, die
  wirklich Geld kosten (z. B. gehostetes Relay/Backup), nie bezahlte Funktionen in der Gruppe.
- **Unbequeme Wahrheit** [wahrscheinlich]: Spenden decken am ehesten Betriebskosten, **kaum Arbeitszeit**. Wer den Aufwand ausgleichen will, braucht zusätzlich Förderungen oder ein Angebot, für das Menschen gern zahlen.
- Ein Premium-Schalter in einer **Gruppen-App** trifft die Falschen: Ein Mitglied ohne Premium blockiert die Gruppe oder wird ausgeschlossen. Das passt nicht zu „Browser = APK“, „freie App-Familie“ und Einladung per Link.

## Die Modelle im Vergleich

| Modell | Kurz | Für | Gegen | Passt zu Fasan? |
|---|---|---|---|---|
| **A. Offen + Spenden** | Alles frei, Spendenbitte (Liberapay, Open Collective, GitHub Sponsors) | Community-Vertrauen, keine Sperren, einfach | Einnahmen klein und schwankend | **Ja** (Grundlage) |
| **B. Offen + Unterstützer-Stufe + Dienste** | wie A, dazu freiwillig „Unterstützer“ (Name auf Dankesliste, Abzeichen ohne Funktion), später bezahlte Dienste mit echten Kosten | planbarer als A, ehrlich (Preis folgt Kosten) | mehr Aufwand (Zahlung, Steuer, Support) | **Ja** (Ausbau) |
| **C. Offener Kern + Premium-Funktionen** | Basis frei, Zusatzfunktionen bezahlt (oft als geschlossener Teil) | planbarer Umsatz | Gruppenproblem, Spaltung der Codebasis, „Browser = APK“ | **Nein** für Gruppenfunktionen |
| **D. Fair Source / „source-available“** | Quelltext lesbar, Weiterverkauf zunächst gesperrt, später Apache/MIT (z. B. FSL: 2 Jahre) | schützt vor Klonen durch Dritte | **kein Open Source** laut OSI, „rechtlich unscharf“, widerspricht dem Beschluss „freie App“ | **Nein** |
| **E. Bezahlte App im Store, Quelltext offen** | Play-Version kostet einmalig, Quelltext/F-Droid/Web frei | kleine Einnahmen ohne Sperre der Funktionen | Store-Gebühren, Käufer zahlen für Bequemlichkeit | **Möglich** als Ergänzung zu A/B |
| **F. Förderungen/Stiftungen** | Fonds für freie Software, Datenschutz | echte Beträge für Arbeitszeit | Antragsaufwand, Wettbewerb | **Prüfen** [nicht geprüft: konkrete Programme] |

## Was die Zahlen sagen

- **Die meisten bekommen nichts.** Tidelift-Befragung 2024: ca. 47 % der Betreuer freier Software bekommen kein Geld; 60 % sehen sich als unbezahlte Hobbyisten; nur 5 % bekommen Geld direkt von Firmen, 3 % von Stiftungen [sicher als Befragungsergebnis, nicht repräsentativ; https://dev.to/tidelift/whos-paying-the-maintainers-donation-programs-employers-and-tidelift-3j4k].
  Eine Zusammenfassung der Ausgabe 2025 nennt 60 % ohne Einkommen und einen Median von 2.000 USD im Jahr bei denen, die etwas bekommen [wahrscheinlich: Zweitquelle, Primärbericht nicht gelesen].
- **Spenden sind ein Zuschuss, kein Gehalt.** Selbst F-Droid mit riesiger Nutzerzahl sammelt über Liberapay etwa 1.500–2.700 USD im Monat (2024/2025) [sicher, https://monitor.f-droid.org/donations]; F-Droid schreibt selbst, es wäre nachhaltig, wenn alle Nutzer 1 USD im Monat gäben [sicher, https://f-droid.org/en/donate].
  Wir sind klein; realistisch: Betriebskosten, kein Einkommen [geraten].
- **„Open Source ist kein Geschäftsmodell“** – Sentry, das deshalb zu „Fair Source“ wechselte [sicher als Aussage: https://techcrunch.com/2024/09/22/some-startups-are-going-fair-source-to-avoid-the-pitfalls-of-open-source-licensing/]. Das gilt für Firmen mit Server-Dienst; bei uns ist die App selbst das Produkt und es gibt kein Konto und keinen Zwangsserver.
- **Store-Kosten** [sicher, https://support.google.com/googleplay/android-developer/answer/112622]: Google Play einmalig 25 USD für das Entwicklerkonto (Zweitquelle, Aug. 2025); Abos ca. 15 % Gebühr, bezahlte Apps/Käufe in der Regel 15 % auf die ersten 1 Mio. USD Jahresumsatz. Die Gebührenregeln wurden 2026 angepasst; vor einer Entscheidung die aktuelle Seite lesen.
  Apple: 99 USD im Jahr [Zweitquelle]. Seit 2026 soll Google eine Identitätsprüfung aller Entwickler verlangen [geraten: nur aus einer Nebenquelle, nicht geprüft].

## Was bei Fasan Split anders ist

- **Echte laufende Kosten:** Relay-Server und Domain (siehe Beschluss 12.10.), GitHub kostet für öffentliche Repos nichts, Play einmalig 25 USD, iOS 99 USD/Jahr (nur wenn iOS kommt). Die Rechenarbeit der Entwicklung (Zeit, Werkzeuge) ist der größere Posten und der, den Spenden am schlechtesten treffen.
- **Netzwerkeffekt:** Eine Rechnung hilft erst, wenn die Gruppe mitmacht. Jede Hürde für das **schwächste Mitglied** (Link öffnen, sofort loslegen, auch im Browser) kostet Nutzer. Premium-Sperren in der Gruppe widersprechen dem.
- **Vertrauen:** keine Telemetrie, keine Konten, offen lesbar. Das ist der Grund, warum Menschen die App wählen. Werbung, versteckte Käufe oder Spendenpopups würden das beschädigen.
- **Beschlüsse, die das Modell binden:** MPL-2.0 und freie App-Familie (07./08.10.), Browser = APK 1:1, kein Fremddienst ohne Freigabe.

## Empfohlener Weg, in Stufen

1. **Jetzt:** Alles offen. LICENSE, Lizenzseite, Marke klären (siehe [README](README.md) Offene Punkte).
2. **Spendenbitte, leise:** Ein Eintrag in den Einstellungen („Fasan Split unterstützen“) und im Repo-README; höchstens ein dezenter Hinweis nach einer abgeschlossenen Abrechnung, wegklickbar, nie blockierend, nur einmal. Text je Sprache in `lib/l10n/`, mit Tutorial-Eintrag (Regel 07.11.).
   Ort: Liberapay (kostenlos, ohne Plattformgebühr) oder Open Collective mit **Fiscal Host** (öffentliche Buchhaltung, Rechts-/Steuerpflicht trägt der Host) [wahrscheinlich: laut Beschreibungen in https://f-droid.org/en/donate und Funding-Übersichten]. GitHub Sponsors zusätzlich, weil das Repo dort liegt.
3. **Transparenz als Werbung:** öffentliche Kostenseite (Server, Konten) und Spendenstand. Das erhöht die Bereitschaft [geraten].
4. **Wenn die Kosten wachsen:** bezahlte **Dienste** mit klarem Preis, z. B. gehostetes Relay und Backup für Gruppen (Preis folgt den Serverkosten), gleiche App, gleicher Code; wer selbst hostet, zahlt nichts. Erst entscheiden, wenn echte Nutzerzahlen und Kosten vorliegen.
5. **Zusätzlich prüfen:** Förderprogramme für freie Software und Datenschutz (Aufwand: Antrag) [nicht geprüft]; Play-Store-Version als freiwilliger „Unterstützer-Kauf“ mit identischem Funktionsumfang [möglich, nicht entschieden].

## Steuer und Rechtsform in Deutschland (grob, [nicht geprüft] – Steuerberatung)

- Spender können Spenden an eine **Privatperson** nicht als Spende absetzen; Spendenquittungen gibt es nur von steuerbegünstigten Organisationen (z. B. gemeinnütziger Verein) [wahrscheinlich; Hintergrund: https://www.lohnsteuer-kompakt.de/en/fag/2013/217/was_kann_ich_als_spenden_und_mitgliedsbeitraege_absetzen].
- Regelmäßige Zahlungen an den Entwickler gelten steuerlich vermutlich als Einnahmen (selbständig oder gewerblich), je nach Höhe mit Anmeldung beim Finanzamt, evtl. Kleinunternehmerregelung bei Umsatzsteuer [wahrscheinlich, nicht geprüft].
- Optionen: (a) als Einzelperson mit Anmeldung; (b) **Fiscal Host** (Open Collective o. Ä.) für Spenden an das Projekt; (c) Verein/gGmbH, wenn der Zweck als gemeinnützig anerkannt wird [nicht geprüft: ob „freie Software für private Abrechnung“ ein steuerbegünstigter Zweck ist]. Vor dem ersten Euro klären.

## Entscheidungen, die beim Nutzer liegen

1. Ziel: **Kosten decken** oder **Arbeitszeit vergüten**? Davon hängt ab, ob A/B reicht oder Förderungen/Dienste nötig sind.
2. Soll es einen **Play-Store-Eintrag** geben (und später iOS)? Das bringt Gebühren und Identitätsprüfung.
3. Spendenbitte: Stil und Stelle (nur Einstellungen oder auch Hinweis nach der Abrechnung).
4. Einzelperson oder Rechtsform; Name, unter dem Geld ankommt.

## Quellen (gelesen 08.11.2026)

- Tidelift-Befragung 2024: https://dev.to/tidelift/whos-paying-the-maintainers-donation-programs-employers-and-tidelift-3j4k ; Folgemeldungen: https://thenewstack.io/open-source-paid-maintainers-keep-code-safer-survey-says/
- F-Droid Spenden: https://f-droid.org/en/donate ; Monitor: https://monitor.f-droid.org/donations
- GitHub Sponsors (Studie): https://arxiv.org/abs/2202.05751
- Fair Source: https://techcrunch.com/2024/09/22/some-startups-are-going-fair-source-to-avoid-the-pitfalls-of-open-source-licensing/ ; https://lucumr.pocoo.org/2024/9/23/fsl-agpl-open-source-businesses/
- Google Play Service-Gebühren: https://support.google.com/googleplay/android-developer/answer/112622
