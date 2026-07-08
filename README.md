# pi-server — Sicherer Multi-Service-Server für Raspberry Pi 4

Setzt `raspberry-pi-4-spezifikation.md` (v2.0) um: Pi-hole, ein statischer
Webserver hinter einem Cloudflare Tunnel, und Uptime Kuma — auf einem
Raspberry Pi 4 mit Raspberry Pi OS Lite (64-bit, headless).

**Invariante:** Von außen ist kein Port offen. Der einzige öffentliche Pfad
zur Webseite läuft über den ausgehenden Cloudflare Tunnel.

```
                     Internet
                        │  (nur AUSGEHEND, verschlüsselt)
                 ┌──────▼──────┐
                 │ Cloudflare  │  DNS · TLS · DDoS-Schutz · versteckt Heim-IP
                 └──────┬──────┘
                        │  outbound-only Tunnel
╔═══════════════════════▼════════════════════════════════╗
║ Raspberry Pi · ufw Default-Deny (eingehend)            ║
║                                                        ║
║  cloudflared ──▶ web (statisch, nur intern)            ║
║                                                        ║
║  pihole (DNS+Adblock, nur LAN)   uptime-kuma (nur LAN) ║
╚════════════════════════════════════════════════════════╝
                        │
                   LAN (${LAN_SUBNET})
          alle Geräte nutzen ${PI_STATIC_IP} als DNS
```

Dieses README ist bewusst sehr ausführlich gehalten: zu **jedem** Wert, den
du eintragen musst, steht dabei, **woher** er kommt und **wie** du ihn
bekommst. Wo es ging, wurde die manuelle Arbeit in Skripte gepackt
(`scripts/setup-env.sh`, `scripts/verify.sh`, `scripts/install-backup-cron.sh`)
— übrig bleiben nur die Schritte, die zwingend eine Cloudflare-/Router-
Weboberfläche brauchen (dort gibt es keine sichere Kommandozeilen-Automatisierung).

---

## Übersicht: Was am Ende automatisiert läuft vs. was du manuell tust

| Automatisiert (per Skript) | Manuell (Web-UI / Router, nicht automatisierbar) |
|---|---|
| System-Update, Docker-Installation | SD-Karte flashen |
| SSH-Härtung, Firewall-Regeln | SSH-Public-Key auf dem Pi hinterlegen |
| `.env` erzeugen inkl. LAN-Erkennung | Domain zu Cloudflare hinzufügen |
| age-Schlüsselpaar erzeugen | Cloudflare Tunnel + Public Hostname anlegen |
| Backup, Verschlüsselung, Rotation, Upload | `rclone config` (OAuth-Login im Browser) |
| Cron-Job für nächtliches Backup | DHCP-Reservierung + Pi-hole als DNS im Router |
| Alle Verifikations-Checks (`verify.sh`) | Realer Restore-Test auf frischer Hardware ([M7]) |

---

## Verwendete Image-Versionen

Gegen die jeweils aktuelle stabile Version verifiziert (Stand: 2026-07-08).
`:latest` wird laut Spezifikation nirgends verwendet.

| Dienst | Image | Tag |
|---|---|---|
| Pi-hole | `pihole/pihole` | `2026.07.2` |
| Web (statisch) | `nginx` | `1.30.3-alpine` |
| Cloudflare Tunnel | `cloudflare/cloudflared` | `2026.7.0` |
| Uptime Kuma | `louislam/uptime-kuma` | `2.4.0` |

Pi-hole v6 setzt das Admin-Passwort über die Environment-Variable
`FTLCONF_webserver_api_password` (verifiziert gegen die offizielle
Docker-Doku von Pi-hole v6; alle FTL-Settings, die per Env gesetzt werden,
sind danach nur noch read-only, d. h. nicht mehr über die Web-UI/CLI änderbar).

Neue Version einsetzen: Tag in `docker-compose.yml` ändern,
`docker compose pull && docker compose up -d`, diese Tabelle aktualisieren.

---

## Alle Werte auf einen Blick — woher sie kommen

Diese Tabelle ist die Kurzreferenz. Die ausführliche Anleitung zu jedem Wert
folgt im Schnellstart weiter unten.

| Variable | Woher bekommst du den Wert? |
|---|---|
| `TZ` | Deine Zeitzone, z. B. `Europe/Berlin`. Liste: [Wikipedia tz-database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
| `LAN_SUBNET` | Wird von `scripts/setup-env.sh` automatisch aus deiner Netzwerkverbindung erkannt. Manuell prüfen: `ip -4 addr show` auf dem Pi |
| `PI_STATIC_IP` | Frei wählbare, feste IP in deinem LAN. Muss anschließend als DHCP-Reservierung im Router eingetragen werden (Anleitung unten) |
| `PORT_PIHOLE_UI` / `PORT_DNS` / `PORT_UPTIME` | Vorgegebene Defaults, i. d. R. unverändert lassen |
| `DOMAIN` | Deine eigene Domain, verwaltet als "Zone" in deinem Cloudflare-Account |
| `PIHOLE_PASSWORD` | Frei wählbar — `scripts/setup-env.sh` kann auch automatisch ein sicheres Passwort generieren |
| `CLOUDFLARE_TUNNEL_TOKEN` | Aus dem Cloudflare Zero-Trust-Dashboard beim Anlegen des Tunnels (Anleitung unten) |
| `BACKUP_REMOTE` | Name des rclone-Remotes, das du mit `rclone config` einrichtest (Anleitung unten) |
| `BACKUP_RETENTION_DAILY` / `_WEEKLY` | Frei wählbare Zahlen, Default 7 / 4 |
| `AGE_RECIPIENT` | Wird von `scripts/setup-env.sh` automatisch erzeugt (age-Schlüsselpaar) |

---

## Voraussetzungen (einmalig, bevor es losgeht)

- Ein Computer (Windows/Mac/Linux) zum Flashen der SD-Karte und für SSH.
- Raspberry Pi 4, microSD-Karte oder USB-SSD, Netzteil, Netzwerkkabel oder WLAN.
- Ein Cloudflare-Account (kostenlos): <https://dash.cloudflare.com/sign-up>
- Eine Domain, die entweder bei Cloudflare registriert ist, oder eine
  bestehende Domain, deren Nameserver du auf Cloudflare umstellst
  (Cloudflare Dashboard → "Add a domain" → Anweisungen dort befolgen).
- Ein Ziel für verschlüsselte Backups, das `rclone` unterstützt (Default:
  OneDrive — jeder von `rclone config` unterstützte Dienst funktioniert).

### SSH-Schlüsselpaar auf deinem Computer erzeugen (falls noch nicht vorhanden)

Das brauchst du, um dich später passwortlos auf dem Pi anzumelden — Pflicht
laut Spezifikation ([M6]: kein Passwort-Login).

```bash
# Mac/Linux (auf deinem Computer, NICHT auf dem Pi):
ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519 -C "pi-server"
```

Windows: PowerShell öffnen und denselben Befehl ausführen (OpenSSH-Client ist
seit Windows 10 vorinstalliert), oder PuTTYgen verwenden.

---

## Schnellstart (Copy & Paste)

### 1. SD-Karte flashen und SSH vorbereiten

1. [Raspberry Pi Imager](https://www.raspberrypi.com/software/) installieren und öffnen.
2. Gerät: **Raspberry Pi 4**. Betriebssystem: **Raspberry Pi OS Lite (64-bit)**.
3. Auf das Zahnrad-Symbol (⚙, "Advanced options") klicken, dort:
   - Hostname vergeben (z. B. `pi-server`)
   - SSH aktivieren → "Allow public-key authentication only" → deinen
     **Public Key** einfügen (Inhalt von `~/.ssh/id_ed25519.pub` von deinem
     Computer, NICHT den privaten Schlüssel!)
   - Falls per WLAN: SSID/Passwort hinterlegen
4. Schreiben, SD-Karte in den Pi, Pi einschalten.

### 2. Verbinden

```bash
# Pi im Netzwerk finden (Standard-Hostname bzw. der oben vergebene):
ping pi-server.local

# Verbinden:
ssh pi@pi-server.local
```

Falls `*.local` bei dir nicht auflöst: IP über die Geräteliste deines
Routers ermitteln (Admin-Oberfläche des Routers, meist erreichbar unter
`192.168.0.1` oder `192.168.1.1` — steht auf der Rückseite des Routers oder
in dessen App).

### 3. Repo klonen

```bash
git clone <URL-DIESES-REPOS> ~/pi-server
cd ~/pi-server
```

### 4. `.env` interaktiv erzeugen

```bash
bash scripts/setup-env.sh
```

Das Skript führt dich Wert für Wert durch die Konfiguration, erklärt bei
jedem Feld woher der Wert kommt, schlägt sinnvolle Defaults vor (u. a.
automatisch erkanntes LAN), generiert bei Bedarf ein sicheres
Pi-hole-Passwort sowie automatisch das age-Schlüsselpaar fürs Backup, und
schreibt am Ende `.env` (mit `chmod 600`).

Falls du den Cloudflare-Tunnel-Token (Schritt 6) noch nicht hast: bei der
Frage einfach Enter drücken und ihn später manuell in `.env` nachtragen —
das Skript weist dich am Ende noch einmal darauf hin.

### 5. System-Bootstrap (Docker, Pakete, Updates)

```bash
bash scripts/00-bootstrap.sh
```

Danach einmal ab- und wieder anmelden (die neue `docker`-Gruppenmitgliedschaft
wird erst nach einem neuen Login aktiv):

```bash
exit
ssh pi@pi-server.local
cd ~/pi-server
```

### 6. Feste IP für den Pi reservieren (Router, manuell)

1. MAC-Adresse des Pi ermitteln:
   ```bash
   ip link show eth0 | awk '/ether/ {print $2}'
   ```
2. In der Router-Admin-Oberfläche (siehe Schritt 2) den Menüpunkt
   **"DHCP-Reservierung"** / **"Static Lease"** / **"Address Reservation"**
   suchen (Bezeichnung variiert je nach Router-Hersteller) und dort die MAC-
   Adresse des Pi fest mit der in `.env` eingetragenen `PI_STATIC_IP`
   verknüpfen.
3. Pi einmal neu starten (`sudo reboot`), damit die feste IP per DHCP
   vergeben wird.

### 7. Härtung: SSH key-only + Firewall Default-Deny

```bash
bash scripts/01-harden.sh
```

Das Skript bricht **mit Fehlermeldung ab**, falls unter
`~/.ssh/authorized_keys` noch kein Public Key hinterlegt ist — das schützt
davor, dich versehentlich selbst auszusperren. (Wenn du in Schritt 1 den Key
im Imager hinterlegt hast, ist das bereits erledigt.)

Verifizieren:

```bash
sudo ufw status verbose
```

Erwartet: `Default: deny (incoming), allow (outgoing)` und Regeln nur für
`${LAN_SUBNET}`.

### 8. Cloudflare Tunnel einrichten (einmalig, im Dashboard)

Das ist der einzige Schritt, der sich nicht per Kommandozeile automatisieren
lässt (OAuth-geschützte Weboberfläche).

1. <https://one.dash.cloudflare.com> öffnen (ggf. Zero Trust kostenlos aktivieren).
2. Links im Menü **Networks → Tunnels → Create a tunnel**.
3. Connector-Typ **Cloudflared** wählen, Namen vergeben (z. B. `pi-server`).
4. Bei "Choose your environment" auf **Docker** klicken. Es erscheint ein
   Befehl wie:
   ```
   docker run cloudflare/cloudflared:... tunnel --no-autoupdate run --token eyJhIjoi...
   ```
   Kopiere **nur** den Teil nach `--token` (die lange Zeichenkette) — das ist
   dein `CLOUDFLARE_TUNNEL_TOKEN`.
5. Trag ihn in `.env` ein:
   ```bash
   nano .env
   # CLOUDFLARE_TUNNEL_TOKEN=<eingefügter Wert>
   ```
6. Im selben Tunnel-Setup (oder danach unter dem Tunnel → **Public Hostname**
   → **Add a public hostname**):
   - Subdomain + Domain = dein `DOMAIN`-Wert aus `.env`
   - Service **Type**: `HTTP`
   - Service **URL**: `web:80`
   - Speichern.

### 9. Dienste starten

```bash
docker compose config   # Syntax-/Wertecheck
docker compose up -d
docker compose ps
```

Alle vier Dienste sollten `running` sein.

### 10. Pi-hole als Netzwerk-DNS eintragen (Router, manuell)

- Web-UI: `http://${PI_STATIC_IP}:${PORT_PIHOLE_UI}` (nur aus dem LAN erreichbar), Login mit `PIHOLE_PASSWORD`.
- In der Router-Admin-Oberfläche: DNS-Server für das LAN (meist unter
  "DHCP-Einstellungen" oder "Internet/WAN") auf `${PI_STATIC_IP}` setzen,
  damit alle Geräte automatisch über Pi-hole auflösen.

### 11. Öffentliche Webseite prüfen

```bash
curl -I https://${DOMAIN}
```

Erwartet: `HTTP/2 200`. `web` selbst hat **keinen** Host-Port — die einzige
Route dorthin führt über `cloudflared`.

### 12. Uptime Kuma einrichten

- Web-UI: `http://${PI_STATIC_IP}:${PORT_UPTIME}` (nur LAN), beim ersten
  Aufruf Admin-Account anlegen.
- Monitore anlegen für: `https://${DOMAIN}` (öffentliche Seite),
  `http://${PI_STATIC_IP}:${PORT_PIHOLE_UI}` (Pi-hole), sowie einen
  Internet-Referenz-Check (z. B. `1.1.1.1`).

### 13. Backup-Ziel verbinden (rclone, interaktiv)

Der Remote-Name muss zum Präfix von `BACKUP_REMOTE` in `.env` passen
(Default: `onedrive`).

```bash
rclone config
```

Im interaktiven Menü (Beispiel für OneDrive):

1. `n` (New remote) → Name eingeben, z. B. `onedrive` (muss zu `BACKUP_REMOTE` passen)
2. Storage-Typ aus der Liste wählen: **Microsoft OneDrive**
3. `client_id` / `client_secret`: leer lassen (Enter)
4. "Edit advanced config?" → `n`
5. "Use web browser to automatically authenticate?" → `y`, falls der Pi
   eine grafische Oberfläche/Browser-Weiterleitung erlaubt. **Headless-Pi
   (Standardfall hier):** `n` wählen und stattdessen auf einem Gerät mit
   Browser `rclone authorize "onedrive"` ausführen, den Code zurück ins
   Terminal auf dem Pi einfügen (das Setup fragt danach).
6. Dein Laufwerk aus der Liste bestätigen (meist `0`), dann `y`.
7. `q` zum Beenden.

Testen:

```bash
rclone lsd "${BACKUP_REMOTE%%:*}:"
```

### 14. Backup ausführen und automatisieren

Manuell testen:

```bash
bash scripts/backup.sh
```

Als nächtlichen Cron-Job einrichten (idempotent — mehrfaches Ausführen legt
den Eintrag nicht doppelt an):

```bash
bash scripts/install-backup-cron.sh
```

### 15. Alles auf einmal verifizieren

```bash
bash scripts/verify.sh
```

Prüft: `docker compose config`, alle Dienste laufen, keine Secrets im Git,
`ufw` Default-Deny aktiv, öffentliche Domain erreichbar — mit
PASS/FAIL-Ausgabe pro Check.

### 16. Restore einmal real testen (Pflicht, [M7])

Siehe Abschnitt "Restore-Prozedur" unten — **vor Abschluss des Setups auf
einem leeren/frischen System einmal tatsächlich durchführen.**

---

## Restore-Prozedur

1. OS auf ein neues Boot-Medium flashen (siehe Schnellstart Schritt 1),
   Pi starten, per SSH verbinden (Schnellstart Schritt 2).
2. Repo klonen (Schnellstart Schritt 3), `scripts/00-bootstrap.sh` und
   `scripts/01-harden.sh` ausführen (Schnellstart Schritt 5 + 7). **Hinweis:**
   `.env` fehlt an dieser Stelle noch — sie kommt erst aus dem Backup
   (nächster Schritt), daher `scripts/setup-env.sh` hier **nicht** ausführen.
3. Deinen privaten age-Schlüssel (den du dir bei der ersten Einrichtung
   gemäß Schnellstart Schritt 4 sicher außerhalb des Pi aufbewahrt hast)
   auf den neuen Pi kopieren, z. B.:
   ```bash
   scp ~/pi-server-age-key.txt pi@pi-server.local:~/.config/age/pi-server.txt
   ```
4. rclone erneut verbinden (Schnellstart Schritt 13 — Zugangsdaten sind
   Account-gebunden, nicht Pi-gebunden, aber die lokale rclone-Config muss
   auf dem neuen System einmal neu erstellt werden).
5. Neuestes Backup holen und entschlüsseln:
   ```bash
   cd ~/pi-server
   REMOTE="onedrive:PiBackups"   # = dein BACKUP_REMOTE aus der alten .env
   LATEST="$(rclone lsf "${REMOTE}" | sort | tail -1)"
   rclone copy "${REMOTE}/${LATEST}" .
   age -d -i ~/.config/age/pi-server.txt -o restore.tar.gz "${LATEST}"
   tar -xzf restore.tar.gz    # stellt data/ und .env wieder her
   rm restore.tar.gz
   ```
6. Dienste starten:
   ```bash
   docker compose up -d
   bash scripts/verify.sh
   ```
7. Verifizieren: Pi-hole-UI erreichbar und filtert, `https://${DOMAIN}`
   liefert die Webseite, Uptime Kuma zeigt die vorherigen Monitore.

**Hinweis zum Restore-Test in diesem Repository:** Der Tar/age-Verschlüsselungs-Roundtrip
(packen → verschlüsseln → entschlüsseln → entpacken → Inhalt identisch) sowie
die Rotationslogik in `scripts/backup.sh` wurden beim Erstellen dieses Repos
lokal verifiziert. Der **vollständige Restore auf echter Pi-Hardware** mit
echtem Cloudflare-Tunnel, echtem rclone-Remote und echtem LAN ([M7]) kann von
einem Coding-Agenten ohne Zugriff auf diese Hardware/Accounts nicht
durchgeführt werden — das musst du einmal real auf deinem Pi nachvollziehen
und abhaken, bevor du das Setup als abgeschlossen betrachtest.

---

## Troubleshooting

| Symptom | Wahrscheinliche Ursache | Prüfen / Fix |
|---|---|---|
| `docker compose ps` zeigt `cloudflared` nicht `running` | Token falsch/leer | `docker compose logs cloudflared`; Token in `.env` neu aus dem Dashboard kopieren |
| `curl -I https://${DOMAIN}` liefert Fehler/Timeout | Public-Hostname-Routing fehlt oder DNS noch nicht propagiert | Im Zero-Trust-Dashboard Public Hostname prüfen; einige Minuten warten |
| Pi-hole-UI unter `PI_STATIC_IP` nicht erreichbar | `PI_STATIC_IP` stimmt nicht mit tatsächlicher Pi-IP überein, oder `ufw`-Regel fehlt | `ip -4 addr show` auf dem Pi vs. `.env` vergleichen; `sudo ufw status verbose` |
| Geräte im LAN nutzen Pi-hole nicht als DNS | Router-DNS-Einstellung noch nicht gesetzt oder Geräte-Cache | Router-DNS-Setting prüfen (Schnellstart Schritt 10); betroffenes Gerät neu verbinden |
| `scripts/01-harden.sh` bricht mit Fehler ab | Kein Public Key in `~/.ssh/authorized_keys` | Key wie in Schnellstart Schritt 1 hinterlegen, dann erneut ausführen |
| `scripts/backup.sh` schlägt bei `rclone` fehl | Remote nicht konfiguriert oder Name stimmt nicht mit `BACKUP_REMOTE` überein | `rclone listremotes`; Schnellstart Schritt 13 wiederholen |

---

## Vom Nutzer auszufüllende Parameter

| Platzhalter | Wo | Bedeutung |
|---|---|---|
| `DOMAIN` | `.env` | Öffentliche Domain der Webseite |
| `CLOUDFLARE_TUNNEL_TOKEN` | `.env` | Tunnel-Token aus dem Zero-Trust-Dashboard |
| `PIHOLE_PASSWORD` | `.env` | Admin-Passwort Pi-hole |
| `LAN_SUBNET` | `.env` | Heimnetz-CIDR, an eigenes LAN anpassen |
| `PI_STATIC_IP` | `.env` | Feste IP des Pi (DHCP-Reservierung im Router) |
| `AGE_RECIPIENT` | `.env` | age-Public-Key zum Verschlüsseln der Backups |
| `BACKUP_REMOTE` | `.env` | rclone-Remote-Ziel, falls nicht OneDrive |

Alle sieben Werte werden von `scripts/setup-env.sh` interaktiv abgefragt
bzw. (bei `AGE_RECIPIENT`) automatisch erzeugt.

`AGE_RECIPIENT` steht nicht in Abschnitt 1/10 der Spezifikation, ist aber für
den in Abschnitt 8.2 geforderten age-basierten Verschlüsselungsschritt
technisch notwendig — als einziger Wert über die SPEC hinaus ergänzt.

## Getroffene Entscheidungen (SPEC Abschnitt 10)

- **cloudflared:** Token-Methode (Default aus SPEC 5.3), Routing im
  Zero-Trust-Dashboard konfiguriert — nicht die alternative `config.yml`.
- **Backup-Verschlüsselung:** `age` (nicht `gpg`) — `age` wird bereits in
  `scripts/00-bootstrap.sh` installiert und passt zur Public-Key-Only-Handhabung.

---

## Nicht im Scope

WireGuard/Tailscale sind bewusst nicht enthalten (SPEC 5.5). Ohne ein
solches Overlay-Netz sind Admin-UIs und Dashboards ausschließlich aus dem
LAN erreichbar. Bei Bedarf: Tailscale nachrüsten (kein Port-Forwarding
nötig) oder self-hosted WireGuard (erfordert eine UDP-Portfreigabe und
widerspricht damit bewusst [N1] — nur mit Bedacht einsetzen).

---

## Repo-Struktur

```
pi-server/
├── docker-compose.yml
├── .env                       # NICHT committen (gitignored)
├── .env.example
├── .gitignore
├── README.md
├── website/
│   └── index.html
├── config/
│   └── nginx/
│       └── default.conf
├── scripts/
│   ├── setup-env.sh           # interaktiver .env-Assistent
│   ├── 00-bootstrap.sh
│   ├── 01-harden.sh
│   ├── install-backup-cron.sh # idempotente Cron-Installation
│   ├── backup.sh
│   └── verify.sh              # buendelt alle Verifikations-Checks
└── data/                       # Laufzeit-Volumes (gitignored)
    ├── pihole/
    └── uptime-kuma/
```
