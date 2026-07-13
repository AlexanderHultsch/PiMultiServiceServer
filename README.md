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

> **Hinweis: Dieses Repository ist öffentlich.** Jeder kann `docker-compose.yml`,
> die Skripte und dieses README lesen. Das ist unproblematisch, solange
> `.env` und `data/` (siehe `.gitignore`) niemals committet werden — dort
> leben alle Geheimnisse (Pi-hole-Passwort, Cloudflare-Token, age-Key).
> Vor jedem `git push`: `git status` prüfen und im Zweifel
> `git ls-files | grep -E '(^|/)\.env$|^data/'` ausführen (muss leer sein,
> wird auch von `scripts/verify.sh` automatisch geprüft).

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
`:latest` wird laut Spezifikation nirgends verwendet. Diese exakten Tags
wurden am 2026-07-13 erfolgreich auf echter Raspberry-Pi-4-Hardware
deployt (`docker compose up -d`, alle vier Container `running`/`healthy`,
öffentliche Seite per `curl -I` mit `HTTP/2 200` über den Cloudflare-Tunnel
bestätigt).

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
- Eine Domain (siehe "Domain besorgen" direkt unten, falls du noch keine hast).
- Ein Ziel für verschlüsselte Backups, das `rclone` unterstützt (Default:
  OneDrive — jeder von `rclone config` unterstützte Dienst funktioniert).

### Domain besorgen: 3 Wege, einer davon ist Pflicht

Du brauchst **irgendeine** Domain, die bei Cloudflare als "Zone" verwaltet
wird (d. h. Cloudflare ist für ihre DNS-Einträge zuständig — unabhängig
davon, wo die Domain ursprünglich gekauft wurde). Es gibt drei Wege dahin;
du brauchst nur **einen**:

| Weg | Wann sinnvoll | Ablauf |
|---|---|---|
| **A. Neu registrieren über Cloudflare Registrar** (empfohlen, wenn du noch **keine** Domain hast — dein Fall) | Einfachster Weg, ein Anbieter für alles, Cloudflare verlangt keinen Aufpreis auf den Einkaufspreis | In <https://dash.cloudflare.com> einloggen, im Bereich zur Domain-Registrierung (Beschriftung z. B. "Register Domains"/"Domain Registration" — Cloudflare ändert Menütexte gelegentlich) Wunschnamen suchen und direkt kaufen. Domain landet automatisch auf Cloudflare-Nameservern, kein Extra-Schritt nötig |
| **B. Bestehende Domain "verbinden" (nur DNS umziehen, Registrierung bleibt woanders)** | Du hast schon eine Domain bei einem anderen Anbieter (Namecheap, IONOS, Strato, …) und willst sie dort nicht kündigen | Cloudflare Dashboard → **Add a domain** → Domain eingeben → Cloudflare zeigt dir 2 Nameserver an → diese beim bisherigen Registrar (dort, wo du die Domain gekauft hast) in den Domain-Einstellungen eintragen. Dauert je nach Anbieter Minuten bis ~24 Std. |
| **C. Domain zu Cloudflare transferieren (Registrierung selbst umziehen)** | Du hast eine Domain woanders und willst auch die Registrierung (Verwaltung/Verlängerung) zu Cloudflare verschieben | Domain muss zuerst per Weg B aktiv auf Cloudflare sein, dann Dashboard → **Domain Registration → Transfer Domains** → Auth-/EPP-Code vom alten Registrar eingeben. Dauert bis zu 10 Tage, meist inkl. einem Jahr Laufzeit-Verlängerung |

**Für dich (noch keine Domain vorhanden): Weg A.** Direkt im Cloudflare
Dashboard eine Domain registrieren — danach ist sie sofort eine Cloudflare-
Zone und du kannst mit Schnellstart Schritt 8 (Tunnel + Public Hostname)
weitermachen. Ein günstiger `.de`/`.com`/`.xyz` o. ä. reicht für dieses
Projekt völlig aus.

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

> **Schon den Imager benutzt und SSH aktiviert (wie z. B. bei dir)?** Dann
> ist Schritt 1 bereits erledigt — überspringe ihn, aber lies den Kasten
> "Prüfen, was der Imager tatsächlich eingerichtet hat" am Ende von Schritt 1
> einmal kurz durch, bevor du mit Schritt 2 weitermachst. Alle anderen
> Schritte (2–16) gelten unverändert für dich.

### 1. SD-Karte flashen und SSH vorbereiten

> **Kein Standard-Benutzer "pi" mehr:** Seit Raspberry Pi OS "Bookworm" gibt
> es keinen vorinstallierten `pi`-Nutzer. Du legst im Imager unter "Advanced
> options" einen **eigenen Benutzernamen** fest. In diesem README steht
> überall `<benutzer>` als Platzhalter dafür — **ersetze ihn in jedem Befehl
> durch den Namen, den du hier vergibst** (in deinem Fall z. B. `alex`).

1. [Raspberry Pi Imager](https://www.raspberrypi.com/software/) installieren und öffnen.
2. Gerät: **Raspberry Pi 4**. Betriebssystem: **Raspberry Pi OS Lite (64-bit)**.
3. Auf das Zahnrad-Symbol (⚙, "Advanced options") klicken, dort:
   - Hostname vergeben (z. B. `pi-server`)
   - **Benutzername und Passwort festlegen** — Passwort trotzdem setzen,
     auch wenn du Public-Key-Login willst (Fallback, falls der Key-Import
     mal nicht greift — siehe Kasten unten, das ist genau das, was bei dir
     passiert ist).
   - SSH aktivieren → "Allow public-key authentication only" → deinen
     **Public Key** einfügen (Inhalt von `~/.ssh/id_ed25519.pub` von deinem
     Computer, NICHT den privaten Schlüssel!). **Wichtig:** manche
     Imager-Versionen übernehmen den eingefügten Key beim Schreiben nicht
     zuverlässig — nach dem ersten Login immer mit dem Befehl im Kasten
     unten verifizieren, statt dich darauf zu verlassen.
   - Falls per WLAN: SSID/Passwort hinterlegen
   - Optional: **"Enable Raspberry Pi Connect"** — dazu mehr im Abschnitt
     "Raspberry Pi Connect" weiter unten; für dieses Setup nicht nötig, aber
     unschädlich, wenn aktiviert.
4. Schreiben, SD-Karte in den Pi, Pi einschalten.

#### Prüfen, was der Imager tatsächlich eingerichtet hat

Nach dem ersten Login **immer** prüfen, ob wirklich ein **Public Key**
hinterlegt wurde (nicht nur Passwort-Login funktioniert) — das ist
Voraussetzung für Schritt 7 (`01-harden.sh` bricht sonst mit einer
Fehlermeldung ab, damit du dich nicht aussperrst):

```bash
cat ~/.ssh/authorized_keys 2>/dev/null && echo "OK: Key vorhanden" || echo "FEHLT: siehe unten"
```

**Falls das leer ist** (der Imager-Key-Import hat nicht funktioniert, du bist
gerade nur per Passwort eingeloggt — das ist ein bekanntes, gelegentliches
Imager-Problem, kein Fehler deinerseits): Key jetzt von deinem Computer aus
nachtragen. Das funktioniert über die bestehende Passwort-Anmeldung:

```bash
# Mac/Linux, auf DEINEM COMPUTER (nicht auf dem Pi), Passwort wird einmal abgefragt:
ssh-copy-id <benutzer>@pi-server.local
```

```powershell
# Windows (PowerShell), auf DEINEM COMPUTER, falls ssh-copy-id fehlt:
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh <benutzer>@pi-server.local "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Danach auf dem Pi erneut prüfen (Befehl oben) — erst wenn "OK: Key
vorhanden" erscheint, weiter mit Schritt 2 bzw. Schritt 7.

### 2. Verbinden

```bash
# Pi im Netzwerk finden (Standard-Hostname bzw. der oben vergebene):
ping pi-server.local

# Verbinden (<benutzer> = dein im Imager gesetzter Benutzername, z.B. alex):
ssh <benutzer>@pi-server.local
```

Falls `*.local` bei dir nicht auflöst: IP über die Geräteliste deines
Routers ermitteln (Admin-Oberfläche des Routers, meist erreichbar unter
`192.168.0.1` oder `192.168.1.1` — steht auf der Rückseite des Routers oder
in dessen App).

### 3. Repo klonen

Raspberry Pi OS Lite hat `git` nicht vorinstalliert — an dieser Stelle ist
`scripts/00-bootstrap.sh` (das `git` mitinstalliert) noch nicht ausgeführt,
also erst kurz manuell nachinstallieren:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/AlexanderHultsch/MultiServiceServer.git ~/pi-server
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

Falls du den Cloudflare-Tunnel-Token (Schritt 8) noch nicht hast: bei der
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
ssh <benutzer>@pi-server.local
cd ~/pi-server
```

### 6. Feste IP für den Pi reservieren (Router, manuell)

**Wichtig zu verstehen:** Diese Reservierung verknüpft eine **MAC-Adresse**
mit einer IP. WLAN und Ethernet (LAN-Kabel) sind auf dem Pi **zwei
unterschiedliche Netzwerk-Interfaces mit je einer eigenen MAC-Adresse**
(`wlan0` bzw. `eth0`). Der Router muss also wissen, **welche der beiden
MAC-Adressen gerade tatsächlich verbunden ist** — reserviere die IP für
genau dieses Interface. Wechselst du später das Interface (z. B. WLAN →
LAN-Kabel), musst du die Reservierung im Router einmalig auf die andere
MAC-Adresse umstellen (Details dazu unten im Kasten "Später von WLAN auf
LAN-Kabel wechseln"). Die IP selbst (`PI_STATIC_IP`) bleibt dabei gleich —
nur die hinterlegte MAC-Adresse ändert sich.

Zweiter entscheidender Punkt: **die IP, die im Router bei der Reservierung
steht, muss exakt mit `PI_STATIC_IP` in deiner `.env` übereinstimmen** — das
passiert nicht automatisch, nur weil ein Schalter aktiv ist.

1. Herausfinden, welches Interface gerade aktiv verbunden ist, und dessen
   MAC-Adresse notieren:
   ```bash
   ip -4 addr show
   ```
   Das Interface mit einer Zeile `inet 192.168.x.x/24 ...` ist das aktive
   (bei dir aktuell `wlan0`). MAC-Adresse dieses Interfaces:
   ```bash
   ip link show wlan0 | awk '/ether/ {print $2}'   # bei Ethernet: eth0 statt wlan0
   ```
2. Aktuellen `PI_STATIC_IP`-Wert aus deiner `.env` nachsehen, damit du weißt,
   welche IP im Router eingetragen sein muss:
   ```bash
   grep -E 'PI_STATIC_IP|LAN_SUBNET' ~/pi-server/.env
   ```

#### FRITZ!Box (sehr verbreitet, z. B. AVM-Router)

1. Im Browser <http://fritz.box> (oder <http://192.168.178.1>) öffnen, mit
   dem Kennwort der FRITZ!Box anmelden.
2. **Heimnetz → Netzwerk → Netzwerkverbindungen**.
3. Den Pi in der Geräteliste suchen (Name `pi-server` bzw. die MAC-Adresse
   des **aktiven** Interfaces von oben) und auf das Stift-/Bearbeiten-Symbol
   klicken.
4. Dort findet sich der Schalter **"IPv4-Adresse dauerhaft zuweisen"**.
   Direkt daneben/darüber steht ein **IPv4-Adressfeld**: genau **dieser
   Wert** ist die IP, die reserviert wird.
   - Steht dort bereits dieselbe Adresse wie dein `PI_STATIC_IP` aus `.env`
     (Schritt 2 oben) → nichts weiter zu tun, einfach mit **Übernehmen**
     bestätigen/speichern.
   - Steht dort eine **andere** Adresse (typischer Fall, wenn der Pi vorher
     automatisch per DHCP eine andere IP bekommen hat): entweder das Feld
     auf den Wert deines `PI_STATIC_IP` ändern (muss innerhalb des von der
     FRITZ!Box verwalteten Bereichs liegen, Standard meist `192.168.178.x`),
     **oder** einfacher: diesen im Router angezeigten Wert 1:1 in `.env`
     als `PI_STATIC_IP` übernehmen (`nano ~/pi-server/.env`).
5. **FRITZ!Box-Standard-LAN ist `192.168.178.0/24`**, nicht `192.168.1.0/24`.
   Falls dein `LAN_SUBNET` in `.env` noch `192.168.1.0/24` ist (z. B. weil
   `setup-env.sh` es nicht korrekt erkannt hat), jetzt auf `192.168.178.0/24`
   korrigieren — sonst funktionieren die `ufw`-Regeln aus Schritt 7 nicht
   für dein tatsächliches LAN.
6. Speichern/**Übernehmen** klicken.

#### Andere Router-Hersteller

Menüpunkt heißt dort meist **"DHCP-Reservierung"** / **"Static Lease"** /
**"Address Reservation"** (Bezeichnung variiert je nach Hersteller); gleiches
Prinzip: MAC-Adresse des **aktiven** Interfaces mit dem `PI_STATIC_IP`-Wert
aus `.env` verknüpfen — im Zweifel lieber die im Router angezeigte/vergebene
Adresse in `.env` übernehmen als umgekehrt.

#### Später von WLAN auf LAN-Kabel wechseln

Falls du (wie aktuell) über WLAN eingerichtet hast und später auf ein
LAN-Kabel wechseln willst: das ändert **nichts** an `.env`,
`docker-compose.yml` oder den `ufw`-Regeln — die IP bleibt identisch, nur
die Netzwerk-Hardware wechselt. Zu erledigen ist dann nur:

1. LAN-Kabel einstecken.
2. Im Router (FRITZ!Box: siehe oben) die **gleiche Reservierung** (gleiche
   `PI_STATIC_IP`) auf die MAC-Adresse von `eth0` umstellen (statt `wlan0`):
   ```bash
   ip link show eth0 | awk '/ether/ {print $2}'
   ```
   Diesen Wert im Router anstelle der bisherigen `wlan0`-MAC-Adresse eintragen.
3. `sudo reboot`, danach mit dem Verifikationsbefehl unten prüfen.
4. Optional, aber empfohlen (vermeidet zwei gleichzeitig aktive Interfaces
   mit unterschiedlichem Verhalten): WLAN auf dem Pi deaktivieren, sobald
   das Kabel dauerhaft verbunden ist:
   ```bash
   sudo rfkill block wifi
   ```

#### Nach dem Speichern

```bash
sudo reboot
```

Nach dem Neustart erneut verbinden und prüfen, dass der Pi tatsächlich die
reservierte Adresse hat (funktioniert unabhängig davon, ob WLAN oder
Ethernet aktiv ist):

```bash
ssh <benutzer>@pi-server.local
ip -4 addr show | grep inet
```

Das Ergebnis muss die in `.env` eingetragene `PI_STATIC_IP` enthalten —
falls nicht, `.env` entsprechend anpassen, bevor du mit Schritt 7 weitermachst.

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
6. Im selben Tunnel-Setup (oder danach unter dem Tunnel → **Published
   Application routes** → **Add published application**, aktuelle
   Cloudflare-Bezeichnung, Stand 2026):
   - **Subdomain**: leer lassen, außer du willst z. B. `www.` davor
   - **Domain**: dein `DOMAIN`-Wert aus `.env` (bei dir `ahultsch.com`)
   - **Path**: leer lassen (matcht alles)
   - **Service URL**: `http://web:80` — **nicht** `localhost`! `web` ist der
     interne Docker-Servicename aus `docker-compose.yml`, nur für
     `cloudflared` im `edge`-Netzwerk erreichbar; Port `80`, weil nginx im
     Container darauf lauscht (kein Host-Port vorhanden, siehe [M8]).
   - **Add route** klicken.

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

## Raspberry Pi Connect — brauchst du das zusätzlich zu SSH?

Du hast Raspberry Pi Connect im Imager aktiviert. Kurz eingeordnet, damit du
entscheiden kannst, ob du es behältst:

**Was es ist:** ein Fernzugriffs-Dienst von der Raspberry Pi Foundation
selbst. Auf Raspberry Pi OS **Lite** (dein Fall, kein Desktop) läuft davon
automatisch nur die "Lite"-Variante mit **reinem Remote-Shell-Zugriff** über
den Browser (kein Bildschirm-Sharing, das gäbe es nur mit Desktop-OS).

**Wie es funktioniert:** Der `rpi-connect`-Dienst baut eine **ausgehende**
Verbindung zu den Relay-/Signalisierungsservern von Raspberry Pi auf
(WebRTC, wie bei Zoom/Meet) und stellt darüber eine Peer-to-Peer-Verbindung
zu deinem Browser her, sobald du dich unter
<https://connect.raspberrypi.com> mit deiner **Raspberry Pi ID** anmeldest.

**Ist das mit diesem Setup kompatibel? Ja:**
- Es öffnet **keinen** eingehenden Port — passt zu [N1]/[M4] (ufw
  Default-Deny bleibt unangetastet, keine zusätzliche `ufw allow`-Regel nötig).
- Es ersetzt nicht die SSH-Härtung aus Schritt 7 — beide laufen unabhängig
  nebeneinander.

**Aber wichtig zu wissen:** Remote Shell über Connect authentifiziert sich
über dein **Raspberry Pi ID**-Konto (Browser-Login + Geräte-Verknüpfung),
**nicht** über deinen SSH-Key und **nicht** über `authorized_keys`. Damit ist
es ein zweiter, von diesem Repo unabhängiger Zugriffsweg auf eine Shell auf
deinem Pi — er wird von `01-harden.sh`/`ufw` nicht mit abgesichert. Die SPEC
selbst kennt nur Tailscale/WireGuard als optionales Zusatz-Zugriffsmodul
(Abschnitt 5.5); Raspberry Pi Connect ist funktional vergleichbar (kein
Port-Forwarding, Fernzugriff von überall), aber ein separates, proprietäres
System der Raspberry Pi Foundation.

**Empfehlung:**
- **Behalten**, wenn du gelegentlich bequem ohne VPN auf eine Shell zugreifen
  willst — dann aber dein Raspberry-Pi-ID-Konto wie ein wichtiges Passwort
  behandeln (einzigartiges, starkes Passwort; 2FA aktivieren, falls von
  Raspberry Pi angeboten).
- **Deaktivieren**, wenn du ausschließlich SSH aus dem LAN nutzen willst und
  keinen zusätzlichen Zugriffsweg möchtest (kleinere Angriffsfläche, näher
  am ursprünglichen SPEC-Scope):
  ```bash
  rpi-connect off
  # optional dauerhaft deinstallieren:
  sudo apt remove --purge rpi-connect-lite
  ```
- Nur Remote-Shell gezielt abschalten, Connect selbst aber installiert lassen:
  ```bash
  rpi-connect shell off
  ```

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
   scp ~/pi-server-age-key.txt <benutzer>@pi-server.local:~/.config/age/pi-server.txt
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
| `-bash: git: command not found` beim Klonen | Raspberry Pi OS Lite hat `git` nicht vorinstalliert, `00-bootstrap.sh` (installiert es) läuft erst nach dem Klonen | `sudo apt update && sudo apt install -y git`, dann erneut klonen (Schnellstart Schritt 3) |
| Nach Reboot nicht mehr unter der reservierten IP erreichbar | Router-Reservierung hängt an der MAC-Adresse des **falschen** Interfaces (z. B. `eth0` reserviert, Pi hängt aber an `wlan0`, oder umgekehrt) | `ip -4 addr show` auf dem Pi, aktives Interface ermitteln, MAC davon mit dem Router-Eintrag abgleichen (Schnellstart Schritt 6) |
| `ufw`-Regeln passen nicht zum tatsächlichen LAN | `LAN_SUBNET` in `.env` enthält eine Host-Adresse statt der Netz-Adresse (z. B. `192.168.178.53/24` statt `192.168.178.0/24`) | `grep LAN_SUBNET .env` prüfen, bei Bedarf korrigieren, `scripts/01-harden.sh` erneut ausführen (aktuelle `setup-env.sh`-Version korrigiert das automatisch) |
| Cloudflare-Dashboard zeigt keinen Menüpunkt "Public Hostname" | Cloudflare hat die Bezeichnung zu "Published Application routes" / "Add published application" geändert (Stand 2026) | Im Tunnel-Detail nach **Published Application routes** suchen, Felder wie in Schnellstart Schritt 8 ausfüllen |

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
