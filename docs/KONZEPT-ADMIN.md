# Konzept: Admin-Bereich und „Alle sind Admins“ (Paket 5, 13.11.)

**Merkmal:** Eintrag `l/all` (true) im signierten Mitgliederdokument. Er zählt nur, wenn der Gründer (`secret.adminPub`) ihn geschrieben hat; fehlt er, ist er aus (ältere Gruppen bleiben unverändert). Das Netz nimmt `l/all` nur von Admins an, die Auswertung (`GroupSession.allAdmins`) verlangt zusätzlich den Gründer als Autor.

**Wirkung:** Ist es an, gelten alle Mitglieder als Admin (`GroupSession.admins`): sie verwalten und laden ein. Der Gründer bleibt der Einzige, der es ändert und der nicht entfernt werden kann.

**Oberfläche:** Schalter „Alle sind Admins“ oben in der Mitgliederliste (nur der Gründer kann ihn ändern, für andere ausgegraut mit Grund). Im Profil eines Mitglieds steht die Admin-Zeile („Zur Verwaltung machen“ / „Verwaltung entziehen“) nur, solange der Schalter aus ist; ist er an, steht dort der Hinweis. Das ist der „Admin-Bereich“ in der kleinsten sinnvollen Form.

**Bewusst offen:** feinere Rechte je Admin (nur Posten ändern, nur Mitglieder verwalten) – sie brauchen ein eigenes Rechtefeld je Mitglied im Mitgliederdokument und kommen erst, wenn der Nutzer sie so will. Bekanntes Risiko: Ist „Alle sind Admins“ an, kann jedes Mitglied Mitglieder entfernen; das steht im Hilfetext des Schalters.
