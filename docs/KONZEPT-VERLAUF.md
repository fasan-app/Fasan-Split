# Konzept: Betragsverlauf einer Person mit Freigabe (Paket 7, 13.11.)

**Frage:** Wie sehen Mitglieder, wie sich der Stand einer Person verändert hat, ohne dass jemand gegen seinen Willen etwas preisgibt?

**Entscheidung:** Freigabe pro Person, Standard **aus** (Nutzer 12.11.). Schalter im eigenen Profil „Meinen Verlauf für Mitglieder zeigen“ (`collab.shareHistory`, nur auf dem Gerät).

**Daten:** Ist der Schalter an, schreibt das Gerät in das eigene Profildokument jeder Gruppe (`profile:<pub>`, mit dem Gruppenschlüssel verschlüsselt) den Eintrag `hist`: bis zu 50 Zeilen `{t: Zeit, n: Titel des Bons, d: Änderung in Cent}`, nur Buchungen dieser Gruppe, neueste zuerst. Aus = Eintrag wird auf null gesetzt. Nur die Person selbst schreibt ihr Profil (bestehende Regel in `group.dart`), „echter Schlüssel je Person“ ist damit der Gruppenschlüssel plus die Unterschrift des Profils.

**Verbergen:** Buchungen verborgener Bons (`Bill.hidden`, Stufe „Beteiligte“) gehen nie hinein. Gesamtsumme und Stand nach der Buchung gehen nicht hinein, nur die Änderung.

**Oberfläche:** Im Profil einer Person Abschnitt „Verlauf der Beträge“: die letzten acht Zeilen, oder „Zeigt ihren oder seinen Verlauf nicht.“ Im eigenen Profil der Schalter mit Hinweis: Absprache, keine technische Sperre.

**Grenzen (ehrlich):** Wer die Freigabe erteilt hat, kann schon Gesehenes nicht zurückholen; alte Geräte anderer Mitglieder behalten Kopien, bis sie aktualisieren. Nur Mitglieder mit Konto können freigeben, Namen ohne Konto haben kein eigenes Profil.
