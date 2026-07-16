# app-example — dynamische Beispiel-App

Winzige Node-App (nur Standardbibliothek), die zeigt, wie eine **dynamische**
Website in diesem Setup läuft: eigener Container, eigenes Verzeichnis, von
Caddy per `reverse_proxy` erreichbar unter `app.<DOMAIN>`.

## Dateien
- `server.js` — der HTTP-Server (Platzhalter, gibt Serverzeit aus).
- `package.json` — Metadaten; hier später echte Abhängigkeiten eintragen.
- `Dockerfile` — baut das Container-Image (Node 24 Alpine).

## Durch deine echte App ersetzen
1. Inhalt dieses Ordners durch deine App ersetzen (muss auf Port `3000`
   lauschen, oder `PORT` im Container anpassen und im Caddyfile den
   `reverse_proxy`-Port angleichen).
2. Falls Abhängigkeiten: im `Dockerfile` die Zeile `RUN npm install --omit=dev`
   einkommentieren.
3. Neu bauen und starten: `docker compose up -d --build app-example`.

## Als eigenes Git-Repo betreiben
Dieser Ordner ist ein Beispiel im Haupt-Repo. Für eine echte App mit eigener
Versionierung: eigenes Git-Repo hierher klonen und den Pfad in der
`.gitignore` des Haupt-Repos eintragen (siehe README, Abschnitt „Weitere
Websites hosten"). Deploy dann per `git pull` + `docker compose up -d --build`.
