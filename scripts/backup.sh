#!/usr/bin/env bash
# Schritt 7 der SPEC (Abschnitt 8.2): Daten-Backup, Verschluesselung, Upload, Rotation.
# Vorgesehen als naechtlicher Cron-Job in der ROOT-crontab (scripts/install-backup-cron.sh).
#
# WARUM ROOT? Die Dateien unter data/ gehoeren den Nutzern der Container
# (root, pihole, ...), nicht dem Login-Nutzer. Ein tar ohne root wuerde an
# "Permission denied" scheitern - beim naechtlichen Cron-Lauf sogar unbemerkt.
# rclone laeuft trotzdem als normaler Nutzer (Besitzer des Repos), damit dessen
# rclone-Konfiguration (~/.config/rclone) verwendet wird und Token-Erneuerungen
# auch wieder dort landen, statt die Datei auf root umzukippen.
#
# RESTORE-PROZEDUR (auf einem frischen System, referenziert vom README):
#   1. Raspberry Pi OS flashen, SSH einrichten (README Schnellstart Schritt 1-2).
#   2. Repo klonen, scripts/00-bootstrap.sh + scripts/01-harden.sh ausfuehren.
#      (.env NICHT per setup-env.sh anlegen - sie kommt gleich aus dem Backup.)
#   3. Privaten age-Schluessel von seinem sicheren Ort (Passwort-Manager, USB)
#      wieder nach ~/.config/age/pi-server.txt kopieren.
#   4. 'rclone config' erneut durchlaufen (gleicher Remote-Name wie vorher).
#   5. Neuestes Backup holen, entschluesseln, entpacken (Remote-Name/Pfad =
#      BACKUP_REMOTE von frueher, z.B. onedrive:PiBackups):
#        cd ~/pi-server
#        LATEST="$(rclone lsf onedrive:PiBackups | sort | tail -1)"
#        rclone copy "onedrive:PiBackups/${LATEST}" .
#        age -d -i ~/.config/age/pi-server.txt -o restore.tar.gz "${LATEST}"
#        sudo tar -xzf restore.tar.gz    # stellt data/ und .env wieder her
#        rm restore.tar.gz "${LATEST}"
#   6. docker compose up -d && bash scripts/verify.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "FEHLER: bitte mit sudo ausfuehren:  sudo bash scripts/backup.sh" >&2
  echo "Grund: data/ enthaelt Dateien der Container-Nutzer, die nur root lesen kann." >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/.env" ]]; then
  echo "FEHLER: ${REPO_ROOT}/.env fehlt - zuerst 'bash scripts/setup-env.sh' ausfuehren." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a; source "${REPO_ROOT}/.env"; set +a

: "${BACKUP_REMOTE:?BACKUP_REMOTE fehlt in .env}"
: "${BACKUP_RETENTION_DAILY:?BACKUP_RETENTION_DAILY fehlt in .env}"
: "${BACKUP_RETENTION_WEEKLY:?BACKUP_RETENTION_WEEKLY fehlt in .env}"
: "${AGE_RECIPIENT:?AGE_RECIPIENT fehlt in .env (age-Public-Key, siehe .env.example)}"

# rclone unter dem Nutzer ausfuehren, dem das Repo gehoert (dort liegt die
# rclone-Konfiguration aus 'rclone config'). -H setzt HOME entsprechend.
# Binary-Pfad vorher aufloesen, da sudo den PATH zuruecksetzt (secure_path).
REPO_OWNER="$(stat -c '%U' "${REPO_ROOT}")"
RCLONE_BIN="$(command -v rclone)" || { echo "FEHLER: rclone nicht installiert (bash scripts/00-bootstrap.sh)" >&2; exit 1; }
run_rclone() { sudo -u "${REPO_OWNER}" -H "${RCLONE_BIN}" "$@"; }

DATE="$(date +%F)"
STAGING_DIR="$(mktemp -d)"
chmod 755 "${STAGING_DIR}"   # damit REPO_OWNER (rclone) hineinlesen darf
ARCHIVE="backup-${DATE}.tar.gz"
ENCRYPTED="${ARCHIVE}.age"

cleanup() { rm -rf "${STAGING_DIR}"; }
trap cleanup EXIT

echo "==> Packe data/ und .env in ${ARCHIVE}"
# tar-Exit-Code 1 ("file changed as we read it") akzeptieren: die Container
# laufen waehrend des Backups weiter und schreiben in ihre Datenbanken.
# Nur Exit-Code >1 (echte Fehler) bricht ab.
set +e
tar --warning=no-file-changed -czf "${STAGING_DIR}/${ARCHIVE}" -C "${REPO_ROOT}" data .env
TAR_RC=$?
set -e
if (( TAR_RC > 1 )); then
  echo "FEHLER: tar schlug fehl (Exit-Code ${TAR_RC})" >&2
  exit "${TAR_RC}"
fi

echo "==> Verschluessele mit age"
age -r "${AGE_RECIPIENT}" -o "${STAGING_DIR}/${ENCRYPTED}" "${STAGING_DIR}/${ARCHIVE}"
rm -f "${STAGING_DIR}/${ARCHIVE}"
chown "${REPO_OWNER}" "${STAGING_DIR}/${ENCRYPTED}"

echo "==> Lade nach ${BACKUP_REMOTE} hoch (als Nutzer ${REPO_OWNER})"
run_rclone copy "${STAGING_DIR}/${ENCRYPTED}" "${BACKUP_REMOTE}"

echo "==> Rotation anwenden (${BACKUP_RETENTION_DAILY} taeglich, ${BACKUP_RETENTION_WEEKLY} woechentlich)"

# Alle vorhandenen Backups (Dateiname traegt das Datum), neueste zuerst.
mapfile -t ALL_BACKUPS < <(run_rclone lsf "${BACKUP_REMOTE}" --files-only | grep -E '^backup-[0-9]{4}-[0-9]{2}-[0-9]{2}\.tar\.gz\.age$' | sort -r)

declare -A KEEP
DAILY_KEPT=0
WEEKLY_KEPT=0
declare -A WEEKLY_SEEN

for f in "${ALL_BACKUPS[@]}"; do
  file_date="${f#backup-}"
  file_date="${file_date%.tar.gz.age}"
  week_key="$(date -d "${file_date}" +%G-%V 2>/dev/null || true)"

  if [[ -z "${week_key}" ]]; then
    continue
  fi

  if (( DAILY_KEPT < BACKUP_RETENTION_DAILY )); then
    KEEP["${f}"]=1
    DAILY_KEPT=$((DAILY_KEPT + 1))
    continue
  fi

  if [[ -z "${WEEKLY_SEEN[${week_key}]:-}" ]] && (( WEEKLY_KEPT < BACKUP_RETENTION_WEEKLY )); then
    KEEP["${f}"]=1
    WEEKLY_SEEN["${week_key}"]=1
    WEEKLY_KEPT=$((WEEKLY_KEPT + 1))
  fi
done

for f in "${ALL_BACKUPS[@]}"; do
  if [[ -z "${KEEP[${f}]:-}" ]]; then
    echo "    loesche altes Backup: ${f}"
    run_rclone deletefile "${BACKUP_REMOTE}/${f}"
  fi
done

echo "==> Backup abgeschlossen: ${ENCRYPTED} (behalten: ${#KEEP[@]} von ${#ALL_BACKUPS[@]})"
