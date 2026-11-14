# Konzept: Admin-Bereich und „Alle sind Admins“ (Paket 5, 13.11.)

**Merkmal:** Eintrag `l/all` (true) im signierten Mitgliederdokument. Er zählt nur, wenn der Gründer (`secret.adminPub`) ihn geschrieben hat; fehlt er, ist er aus (ältere Gruppen bleiben unverändert). Das Netz nimmt `l/all` nur von Admins an, die Auswertung (`GroupSession.allAdmins`) verlangt zusätzlich den Gründer als Autor.

**Wirkung:** Ist es an, gelten alle Mitglieder als Admin (`GroupSession.admins`): sie verwalten und laden ein. Der Gründer bleibt der Einzige, der es ändert und der nicht entfernt werden kann.

**Oberfläche:** Schalter „Alle sind Admins“ oben in der Mitgliederliste (nur der Gründer kann ihn ändern, für andere ausgegraut mit Grund). Im Profil eines Mitglieds steht die Admin-Zeile („Zur Verwaltung machen“ / „Verwaltung entziehen“) nur, solange der Schalter aus ist; ist er an, steht dort der Hinweis. Das ist der „Admin-Bereich“ in der kleinsten sinnvollen Form.

**Rechte der Gruppe (14.11., Paket 5b):** Eintrag `l/rights` im Mitgliederdokument (nur von Admins, zählt nur von Admins): je Recht „bills“ (Rechnungen anlegen), „edit“ (Rechnungen/Posten ändern), „notes“ (Notizen) entweder alle (Standard) oder nur Admins. Durchsetzung auf jedem Handy beim Empfang (`_accept`, wie das Vorhängeschloss) und beim Schreiben (`_syncStore`: ohne „bills“ bleibt eine neue Rechnung lokal, ohne „edit“ kommt die eigene Änderung zurück); Oberfläche: Bon schreibgeschützt mit Hinweis, Notizen-Knopf erklärt die Sperre. Bewusst nicht als Recht: Einladen/Entfernen (schon Admin-Sache) und Gruppe umbenennen/löschen (lokal je Gerät). Bekanntes Risiko: Ist „Alle sind Admins“ an, kann jedes Mitglied Mitglieder entfernen; das steht im Hilfetext des Schalters.
