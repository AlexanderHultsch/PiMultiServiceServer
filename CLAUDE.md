# CLAUDE.md — Arbeitsanweisung für Claude Code

## Kontext
Dieses Repo setzt die Spezifikation in `raspberry-pi-4-spezifikation.md` um.
Diese SPEC ist die **maßgebliche Quelle der Wahrheit**. Lies sie vollständig, bevor du handelst.
Ziel: sicherer Multi-Service-Server (Pi-hole, statischer Webserver, Cloudflare Tunnel, Uptime Kuma) auf einem Raspberry Pi 4.

Diese Datei gilt sowohl für den **initialen Aufbau** des Repos als auch für
**spätere Debugging-/Wartungs-Sitzungen**, die direkt auf dem Pi selbst
gestartet werden (`claude` im Projektordner, siehe README Abschnitt "Claude
Code direkt auf dem Pi" bzw. SPEC Abschnitt 5.6). In beiden Fällen gelten
dieselben Regeln.

## Umgebung
- Läuft auf dem Raspberry Pi 4 (Raspberry Pi OS Lite, 64-bit, headless).
- Docker + Docker Compose vorhanden (sonst zuerst `scripts/00-bootstrap.sh`).
- Repo-Wurzel: `~/pi-server`. Arbeite immer von hier.
- `sudo` verfügbar; sparsam und nur wie in den Skripten vorgesehen einsetzen.

## Closed-Loop-Arbeitsweise (verbindlich)
Arbeite die Umsetzungstabelle (SPEC Abschnitt 9) **Schritt für Schritt** ab.
Für JEDEN Schritt:
1. Umsetzen (Datei/Skript erzeugen oder Befehl ausführen).
2. Mit einem konkreten Check verifizieren.
3. Erst weitergehen, wenn die Definition of Done erfüllt ist. Bei Fehler: Ausgabe lesen, Ursache beheben, erneut prüfen.

Verifikations-Checks (auch gebündelt über `bash scripts/verify.sh`):
- Compose gültig: `docker compose config`
- Dienste laufen: `docker compose ps`
- Firewall: `sudo ufw status verbose` → Default-Deny + nur LAN-Regeln
- Web öffentlich erreichbar: `curl -I https://<DOMAIN>`
- Keine Secrets im Git: `git ls-files | grep -E '(^|/)\.env$|^data/'` muss leer sein

## Harte Regeln (SPEC Abschnitt 3 — NIEMALS verletzen)
- Kein `:latest`; alle Images auf konkrete Version pinnen (Tag in README notieren).
- `.env`, `data/`, Backup-Artefakte (`*.tar.gz`, `*.age`) NIE committen.
- Keine eingehenden Ports öffnen; `web` bekommt KEINEN `ports:`-Eintrag.
- Admin-UIs (`pihole`, `uptime-kuma`) nur an `${PI_STATIC_IP}` binden.
- SSH key-only; kein Passwort-Login, kein Root-Login.
- Vor Abschluss: Backup-Restore einmal real testen.
- Läuft eine Claude Code CLI auf dem Pi (SPEC 5.6): niemals als
  Hintergrunddienst/Autostart einrichten (kein systemd-Unit, kein Cronjob) —
  nur On-Demand-Aufruf.

## Vorgehen bei Unsicherheit
- Versionsabhängige Details (z. B. Pi-hole-v6-Env-Variablennamen, Image-Tags, Cloudflare-Dashboard-Wortlaut) gegen die offizielle Doku verifizieren — nicht raten.
- Zerstörerische Befehle (`rm -rf`, `docker volume rm`, `ufw reset`) vorher ankündigen und bestätigen lassen.
- **Dies ist ein LIVE-Server** (DNS fürs ganze LAN + öffentliche Webseite). Handle vorsichtig; keine breiten Löschaktionen ohne Rückfrage.

## Nicht im Scope
- WireGuard/Tailscale nur, wenn ausdrücklich angefordert (SPEC 5.5).
