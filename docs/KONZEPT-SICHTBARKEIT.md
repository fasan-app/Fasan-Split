# Konzept: Sichtbarkeit je Rechnung (Paket G, Entwurf 10.11.)

Auftrag (Nutzer 09.11. 19:04, ANFORDERUNGEN 18): Wer später in eine Gruppe eingeladen wird, soll nicht automatisch alte Rechnungen
sehen. Stufen: **Alle** | **Beteiligte** | **nur Beträge**. Rechnungen, bei denen nicht alle dabei waren, auf Wunsch nur für die Beteiligten.
Datenschutz steht über allem (CLAUDE.md): „versteckt“ muss wirklich unlesbar sein, nicht nur nicht angezeigt.

## Ehrliche Lage (belegt im Code, `collab/group.dart`)
- Eine Gruppe hat **einen** Schlüssel K. Jedes Dokument (`bill:<id>`, Chat, Profile) ist damit verschlüsselt, jedes Mitglied bekommt K bei der Aufnahme.
- Wer K hat, kann alles lesen, was je mit K verschlüsselt wurde und auf den Relays liegt. Ein Ausblenden nur in der Oberfläche
  (Beitrittszeitpunkt prüfen) wäre **keine** Privatsphäre: die Daten kämen trotzdem an. Das darf nicht „versteckt“ heißen.
- Beim Entfernen eines Mitglieds gibt es schon einen Schlüsselwechsel (Test `core_admin_test`, „Mitglied entfernen“). Das ist der Baustein.

## Vorschlag: Schlüssel je Rechnung (K_b)
1. Rechnung mit Stufe **Beteiligte**: Die Rechnung bekommt einen eigenen Zufallsschlüssel K_b. Ihr Dokument wird mit K_b verschlüsselt, nicht mit K.
2. K_b wird an jedes berechtigte Mitglied einzeln verschlüsselt gesendet (an dessen öffentlichen Schlüssel, wie die Aufnahme-Antwort).
   Berechtigt = Mitglied, dessen Person im Bon steht (Verknüpfung „Person ↔ Mitglied“ gibt es: `personsOf`/`memberOfPerson`), plus Ersteller und Admin.
3. Wer später beitritt, bekommt nur K, kein K_b: Die alten Rechnungen bleiben für ihn Rauschen. Wird er im Bon eingetragen, bekommt er K_b nachgeliefert.
4. Stufe **nur Beträge**: zwei Dokumente je Rechnung, ein offenes mit Summe, Zahler und Anteilen je Person (ohne Posten-Namen, Fotos, Notizen) unter K, ein
   vollständiges unter K_b.
5. Stufe **Alle** bleibt wie heute (Standard, keine Änderung für bestehende Gruppen).

## Was das kostet (nicht geprüft)
- Neues Dokument-Schema (`docId` → welcher Schlüssel), Schlüsselverteilung, Nachliefern, Umgang mit verlorenen Schlüsseln (Gerätewechsel: Sicherungsdatei muss K_b enthalten).
- Fotos (`photo_sync`) hängen heute an K; müssten mit K_b verschlüsselt werden.
- Chat-Karten „Posten schicken“ zeigen Posten aus der Rechnung: bei Stufe Beteiligte nur für Berechtigte lesbar.
- Tests: Zwei-Telefone-Test mit drittem, später beigetretenem Telefon, das die Rechnung **nicht** entschlüsseln kann (echter Nachweis, nicht Oberfläche).

## Offene Fragen mit Standard (Sitzung entscheidet, wenn der Nutzer nicht anders sagt)
1. Standardstufe für neue Rechnungen in Gruppen: **Alle** (heutiges Verhalten).
2. Beim Einladen: Frage „Alte Rechnungen zeigen?“ nur, wenn es Rechnungen gibt; Standard **ja** (heutiges Verhalten); „nein“ setzt alle bestehenden auf Beteiligte.
3. Reihenfolge: erst Stufe **Beteiligte** (K_b), dann **nur Beträge**.
