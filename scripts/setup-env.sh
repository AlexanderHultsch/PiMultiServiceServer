#!/usr/bin/env bash
# Interaktiver Assistent fuer .env (SPEC Abschnitt 1 + 10).
# Fragt jeden Wert einzeln ab, erklaert woher er kommt, schlaegt sinnvolle
# Defaults vor (LAN-Erkennung, age-Key-Erzeugung) und schreibt am Ende .env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  read -r -p ".env existiert bereits. Ueberschreiben? [y/N] " confirm
  [[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Abgebrochen, bestehende .env bleibt unveraendert."; exit 0; }
fi

echo "=================================================================="
echo " pi-server Setup-Assistent"
echo " Enter uebernimmt jeweils den in [Klammern] vorgeschlagenen Wert."
echo "=================================================================="

ask() {
  # ask <Variablenname> <Erklaerungstext> <Default>
  local __varname="$1" __hint="$2" __default="$3" __input
  echo
  echo "--- ${__varname} ---"
  echo "${__hint}"
  read -r -p "> [${__default}] " __input
  printf -v "$__varname" '%s' "${__input:-${__default}}"
}

ask_secret() {
  # ask_secret <Variablenname> <Erklaerungstext>
  local __varname="$1" __hint="$2" __input
  echo
  echo "--- ${__varname} ---"
  echo "${__hint}"
  read -r -s -p "> " __input
  echo
  printf -v "$__varname" '%s' "${__input}"
}

# --- Netzwerk-Erkennung als Vorschlag ---
DETECTED_IP=""
DETECTED_SUBNET=""
if command -v ip >/dev/null 2>&1; then
  DETECTED_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')"
  if [[ -n "${DETECTED_IP}" ]]; then
    DETECTED_SUBNET="$(ip -4 addr show 2>/dev/null | awk -v ip="${DETECTED_IP}" '$0 ~ ip {print $2}' | head -1)"
  fi
fi
DETECTED_SUBNET="${DETECTED_SUBNET:-192.168.1.0/24}"
DETECTED_IP="${DETECTED_IP:-192.168.1.10}"
# Auf ein /24 normalisieren, falls eine Host-Adresse mit /32 o.ae. erkannt wurde
DETECTED_SUBNET="$(echo "${DETECTED_SUBNET}" | sed -E 's#^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/.*#\1.0/24#')"

ask TZ "Zeitzone, z.B. 'Europe/Berlin'. Liste: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones" "Europe/Berlin"

ask LAN_SUBNET "Dein Heimnetz-CIDR (die NETZ-Adresse, nicht die IP des Pi selbst - z.B. 192.168.178.0/24).
Falls falsch: auf dem Pi 'ip -4 addr show' ausfuehren und das Netz hinter deiner IP ablesen (z.B. 192.168.1.0/24)." "${DETECTED_SUBNET}"
# Falls versehentlich eine Host-Adresse statt der Netz-Adresse eingegeben wurde
# (z.B. 192.168.178.53/24 statt 192.168.178.0/24), automatisch korrigieren.
LAN_SUBNET="$(echo "${LAN_SUBNET}" | sed -E 's#^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+(/.*)?$#\1.0/24#')"

ask PI_STATIC_IP "Die feste IP, die der Pi im LAN bekommen soll (DHCP-Reservierung im Router -
siehe README Abschnitt 'Feste IP fuer den Pi reservieren'). Vorschlag = aktuell erkannte IP dieses Geraets." "${DETECTED_IP}"

ask PORT_PIHOLE_UI "Host-Port fuer die Pi-hole Weboberflaeche (nur im LAN erreichbar). In der Regel unveraendert lassen." "8080"
ask PORT_DNS "Port fuer DNS. Muss 53 sein, ausser du weisst genau warum du das aenderst." "53"
ask PORT_UPTIME "Host-Port fuer Uptime Kuma (nur im LAN erreichbar)." "3001"

ask DOMAIN "Deine oeffentliche Domain (z.B. example.com oder status.example.com).
Muss als 'Zone' in deinem Cloudflare-Account verwaltet werden (Nameserver auf Cloudflare zeigend).
Falls du noch keine Domain hast: https://dash.cloudflare.com -> Registrar, oder eine bestehende Domain
zu Cloudflare umziehen (Website hinzufuegen -> Nameserver beim aktuellen Registrar umstellen)." ""
while [[ -z "${DOMAIN}" ]]; do
  echo "DOMAIN darf nicht leer sein."
  ask DOMAIN "Deine oeffentliche Domain, siehe Hinweis oben." ""
done

ask_secret PIHOLE_PASSWORD "Admin-Passwort fuer die Pi-hole Weboberflaeche. Frei waehlbar, wird jetzt nur lokal
in .env gespeichert (nicht auf einem Server abgefragt). Leer lassen = zufaelliges, sicheres Passwort wird erzeugt."
if [[ -z "${PIHOLE_PASSWORD}" ]]; then
  PIHOLE_PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
  echo "Generiertes Pi-hole-Passwort: ${PIHOLE_PASSWORD}"
  echo "(Notiere es dir jetzt - es wird nur einmal angezeigt und steht danach in .env.)"
elif [[ "${#PIHOLE_PASSWORD}" -lt 8 ]]; then
  echo "WARNUNG: Das ist ein sehr kurzes Passwort (${#PIHOLE_PASSWORD} Zeichen)."
  echo "Die Pi-hole-UI ist zwar nur im LAN erreichbar, trotzdem empfehlenswert:"
  echo "spaeter in der Pi-hole-UI unter Settings > Web Interface / API ein laengeres setzen."
fi

ask_secret CLOUDFLARE_TUNNEL_TOKEN "Tunnel-Token aus dem Cloudflare Zero Trust Dashboard:
https://one.dash.cloudflare.com -> Networks -> Tunnels -> Create a tunnel -> Cloudflared ->
Name vergeben -> bei 'Choose your environment' auf 'Docker' klicken.
Dort wird ein 'docker run ...--token eyJ...' Befehl angezeigt - kopiere NUR den Wert nach --token.
Falls du das jetzt noch nicht griffbereit hast: Enter druecken und spaeter manuell in .env eintragen."

ask BACKUP_REMOTE "rclone-Remote-Ziel fuer verschluesselte Backups, Format '<remote-name>:<Pfad>'.
Der Remote-Name muss mit 'rclone config' auf diesem Pi eingerichtet sein (README Abschnitt Backup)." "onedrive:PiBackups"
ask BACKUP_RETENTION_DAILY "Wie viele taegliche Backup-Staende sollen behalten werden?" "7"
ask BACKUP_RETENTION_WEEKLY "Wie viele woechentliche Backup-Staende sollen zusaetzlich behalten werden?" "4"

# --- age-Schluesselpaar automatisch erzeugen, falls noch keins vorhanden ---
AGE_KEY_FILE="${HOME}/.config/age/pi-server.txt"
echo
echo "--- AGE_RECIPIENT (Backup-Verschluesselung) ---"
if [[ -f "${AGE_KEY_FILE}" ]]; then
  echo "Vorhandenes age-Schluesselpaar gefunden: ${AGE_KEY_FILE}"
else
  echo "Kein age-Schluesselpaar gefunden - erzeuge eins unter ${AGE_KEY_FILE}"
  mkdir -p "$(dirname "${AGE_KEY_FILE}")"
  age-keygen -o "${AGE_KEY_FILE}" 2>/tmp/age-keygen.$$.log
  cat /tmp/age-keygen.$$.log
  rm -f /tmp/age-keygen.$$.log
fi
AGE_RECIPIENT="$(grep 'public key' "${AGE_KEY_FILE}" -i | awk '{print $NF}')"
echo "Verwende Public Key: ${AGE_RECIPIENT}"
echo "WICHTIG: ${AGE_KEY_FILE} enthaelt den PRIVATEN Schluessel und wird NICHT automatisch"
echo "gesichert. Kopiere ihn jetzt an einen sicheren Ort ausserhalb des Pi (Passwort-Manager, USB)."

cat > "${ENV_FILE}" <<EOF
TZ=${TZ}
LAN_SUBNET=${LAN_SUBNET}
PI_STATIC_IP=${PI_STATIC_IP}
PORT_PIHOLE_UI=${PORT_PIHOLE_UI}
PORT_DNS=${PORT_DNS}
PORT_UPTIME=${PORT_UPTIME}
DOMAIN=${DOMAIN}
PIHOLE_PASSWORD=${PIHOLE_PASSWORD}
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
BACKUP_REMOTE=${BACKUP_REMOTE}
BACKUP_RETENTION_DAILY=${BACKUP_RETENTION_DAILY}
BACKUP_RETENTION_WEEKLY=${BACKUP_RETENTION_WEEKLY}
AGE_RECIPIENT=${AGE_RECIPIENT}
EOF
chmod 600 "${ENV_FILE}"

echo
echo "=================================================================="
echo ".env geschrieben nach ${ENV_FILE} (chmod 600)."
if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN}" ]]; then
  echo "HINWEIS: CLOUDFLARE_TUNNEL_TOKEN ist noch leer - vor 'docker compose up -d'"
  echo "in .env nachtragen, sonst startet der cloudflared-Container nicht erfolgreich."
fi
echo "Naechster Schritt: bash scripts/01-harden.sh"
echo "=================================================================="
