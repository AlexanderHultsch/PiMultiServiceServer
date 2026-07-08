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

Wenn du eine neue Version einsetzen willst: Tag in `docker-compose.yml`
ändern, `docker compose pull && docker compose up -d`, danach diese Tabelle
aktualisieren.

---

## Voraussetzungen

- Raspberry Pi 4, Raspberry Pi OS Lite (64-bit), SSH-Zugriff mit Public Key.
- Ein Domain-Name, den du auf Cloudflare verwaltest (`DOMAIN`).
- Ein Cloudflare-Account mit Zero Trust (kostenlos) für den Tunnel.
- Ein rclone-fähiges Remote-Ziel für Backups (Default: OneDrive).
- Eine DHCP-Reservierung im Router für `PI_STATIC_IP` (feste IP im LAN).

---

## Schnellstart (Copy & Paste)

Alle Blöcke der Reihe nach auf dem Pi ausführen (per SSH). Ersetze
Platzhalter, bevor du fortfährst.

### 1. Repo klonen

```bash
git clone <URL-DIESES-REPOS> ~/pi-server
cd ~/pi-server
```

### 2. `.env` anlegen und ausfüllen

```bash
cp .env.example .env
nano .env
```

Auszufüllende Werte (siehe Tabelle unten) — mindestens:
`LAN_SUBNET`, `PI_STATIC_IP`, `DOMAIN`, `PIHOLE_PASSWORD`,
`CLOUDFLARE_TUNNEL_TOKEN`, `AGE_RECIPIENT`.

### 3. System-Bootstrap (Docker, Pakete, Updates)

```bash
bash scripts/00-bootstrap.sh
```

Falls Docker neu installiert wurde: einmal ab- und wieder anmelden
(Gruppenmitgliedschaft `docker` wird erst nach neuem Login aktiv), dann
weiter mit Schritt 4.

### 4. Härtung: SSH key-only + Firewall Default-Deny

```bash
bash scripts/01-harden.sh
```

**Achtung:** Stelle vor diesem Schritt sicher, dass dein SSH-Public-Key
bereits in `~/.ssh/authorized_keys` hinterlegt ist — danach ist kein
Passwort-Login mehr möglich.

Verifizieren:

```bash
sudo ufw status verbose
```

Erwartet: `Default: deny (incoming), allow (outgoing)` und Regeln nur für
`${LAN_SUBNET}`.

### 5. Cloudflare Tunnel einrichten (einmalig, im Dashboard)

1. Cloudflare Zero Trust Dashboard → **Networks → Tunnels → Create a tunnel**.
2. Connector-Typ **Docker** wählen → den angezeigten Token kopieren.
3. Token in `.env` als `CLOUDFLARE_TUNNEL_TOKEN` eintragen.
4. Im Tunnel unter **Public Hostname**: `${DOMAIN}` → Service
   `HTTP` → `web:80` eintragen.

### 6. Dienste starten

```bash
docker compose config   # Syntax-/Wertecheck
docker compose up -d
docker compose ps
```

Alle vier Dienste sollten `running`/`healthy` sein.

### 7. Pi-hole als Netzwerk-DNS eintragen

- Web-UI: `http://${PI_STATIC_IP}:${PORT_PIHOLE_UI}` (nur aus dem LAN erreichbar).
- Im Router: DNS-Server für das LAN auf `${PI_STATIC_IP}` setzen, damit alle
  Geräte über Pi-hole auflösen.

### 8. Öffentliche Webseite prüfen

```bash
curl -I https://${DOMAIN}
```

Erwartet: `HTTP/2 200`. `web` selbst hat **keinen** Host-Port — die einzige
Route dorthin führt über `cloudflared`.

### 9. Uptime Kuma einrichten

- Web-UI: `http://${PI_STATIC_IP}:${PORT_UPTIME}` (nur LAN), Admin-Account
  beim ersten Aufruf anlegen.
- Monitore anlegen für: `https://${DOMAIN}` (öffentliche Seite),
  `http://${PI_STATIC_IP}:${PORT_PIHOLE_UI}` (Pi-hole), sowie einen
  Internet-Referenz-Check (z. B. `1.1.1.1`).

### 10. Backup einrichten

age-Schlüsselpaar erzeugen (falls noch nicht vorhanden) und Public Key in
`.env` eintragen:

```bash
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/pi-server.txt
# Ausgabe "Public key: age1..." in .env als AGE_RECIPIENT eintragen.
```

**Wichtig:** `~/.config/age/pi-server.txt` enthält den privaten Schlüssel.
Er wird **nicht** automatisch gesichert — ohne ihn sind Backups nicht
entschlüsselbar. Sicher außerhalb des Pi aufbewahren (Passwort-Manager, USB,
Safe).

rclone-Remote konfigurieren (interaktiv, einmalig):

```bash
rclone config
# Remote-Name muss zum Präfix von BACKUP_REMOTE passen, z.B. "onedrive"
```

Backup manuell testen:

```bash
bash scripts/backup.sh
```

Als nächtlichen Cron-Job einrichten (läuft täglich um 03:00):

```bash
(crontab -l 2>/dev/null; echo "0 3 * * * cd $HOME/pi-server && ./scripts/backup.sh >> $HOME/pi-server-backup.log 2>&1") | crontab -
```

### 11. Restore einmal real testen (Pflicht, [M7])

Siehe Abschnitt "Restore-Prozedur" unten — **vor Abschluss des Setups auf
einem leeren/frischen System einmal tatsächlich durchführen.**

---

## Verifikations-Checks (jederzeit wiederholbar)

```bash
docker compose config                 # Compose gültig
docker compose ps                     # Dienste laufen
sudo ufw status verbose               # Default-Deny + nur LAN-Regeln
curl -I https://${DOMAIN}             # Web öffentlich erreichbar
git ls-files | grep -E '(^|/)\.env$|^data/'   # muss LEER sein (keine Secrets im Git)
```

---

## Restore-Prozedur

1. OS auf ein neues Boot-Medium flashen (Raspberry Pi OS Lite, 64-bit),
   Pi starten, per SSH verbinden.
2. `scripts/00-bootstrap.sh` und `scripts/01-harden.sh` ausführen (siehe
   Schnellstart 3–4).
3. Repo klonen:
   ```bash
   git clone <URL-DIESES-REPOS> ~/pi-server && cd ~/pi-server
   ```
4. Neuestes Backup vom Remote holen und entschlüsseln (privaten age-Key
   bereithalten, siehe Schnellstart 10):
   ```bash
   rclone lsf "${BACKUP_REMOTE}" | sort | tail -1   # neuestes Backup ermitteln
   rclone copy "${BACKUP_REMOTE}/<neuestes-backup>.tar.gz.age" .
   age -d -i ~/.config/age/pi-server.txt -o restore.tar.gz <neuestes-backup>.tar.gz.age
   tar -xzf restore.tar.gz    # stellt data/ und .env wieder her
   rm restore.tar.gz
   ```
5. Dienste starten:
   ```bash
   docker compose up -d
   docker compose ps
   ```
6. Verifizieren: Pi-hole-UI erreichbar und filtert, `https://${DOMAIN}`
   liefert die Webseite, Uptime Kuma zeigt die vorherigen Monitore.

**Hinweis zum Restore-Test in diesem Repository:** Der Tar/age-Verschlüsselungs-Roundtrip
(packen → verschlüsseln → entschlüsseln → entpacken → Inhalt identisch) wurde
beim Erstellen dieses Repos lokal verifiziert, ebenso die Rotationslogik in
`scripts/backup.sh`. Der **vollständige Restore auf echter Pi-Hardware** mit
echtem Cloudflare-Tunnel, echtem rclone-Remote und echtem LAN ([M7]) kann von
einem Coding-Agenten ohne Zugriff auf diese Hardware/Accounts nicht
durchgeführt werden — das musst du einmal real auf deinem Pi nachvollziehen
und abhaken, bevor du das Setup als abgeschlossen betrachtest.

---

## Vom Nutzer auszufüllende Parameter

| Platzhalter | Wo | Bedeutung |
|---|---|---|
| `DOMAIN` | `.env` | Öffentliche Domain der Webseite |
| `CLOUDFLARE_TUNNEL_TOKEN` | `.env` | Tunnel-Token aus dem Zero-Trust-Dashboard |
| `PIHOLE_PASSWORD` | `.env` | Admin-Passwort Pi-hole |
| `LAN_SUBNET` | `.env` | Heimnetz-CIDR, an eigenes LAN anpassen |
| `PI_STATIC_IP` | `.env` | Feste IP des Pi (DHCP-Reservierung im Router) |
| `AGE_RECIPIENT` | `.env` | age-Public-Key zum Verschlüsseln der Backups (siehe Schnellstart 10) |
| `BACKUP_REMOTE` | `.env` | rclone-Remote-Ziel, falls nicht OneDrive |

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
├── .env                      # NICHT committen (gitignored)
├── .env.example
├── .gitignore
├── README.md
├── website/
│   └── index.html
├── config/
│   └── nginx/
│       └── default.conf
├── scripts/
│   ├── 00-bootstrap.sh
│   ├── 01-harden.sh
│   └── backup.sh
└── data/                      # Laufzeit-Volumes (gitignored)
    ├── pihole/
    └── uptime-kuma/
```
