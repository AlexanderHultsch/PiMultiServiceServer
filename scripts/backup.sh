#!/usr/bin/env bash
# Schritt 7 der SPEC (Abschnitt 8.2): Daten-Backup, Verschluesselung, Upload, Rotation.
# Vorgesehen als naechtlicher Cron-Job (siehe README).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
set -a; source "${REPO_ROOT}/.env"; set +a

: "${BACKUP_REMOTE:?BACKUP_REMOTE fehlt in .env}"
: "${BACKUP_RETENTION_DAILY:?BACKUP_RETENTION_DAILY fehlt in .env}"
: "${BACKUP_RETENTION_WEEKLY:?BACKUP_RETENTION_WEEKLY fehlt in .env}"
: "${AGE_RECIPIENT:?AGE_RECIPIENT fehlt in .env (age-Public-Key, siehe .env.example)}"

DATE="$(date +%F)"
STAGING_DIR="$(mktemp -d)"
ARCHIVE="backup-${DATE}.tar.gz"
ENCRYPTED="${ARCHIVE}.age"

cleanup() { rm -rf "${STAGING_DIR}"; }
trap cleanup EXIT

echo "==> Packe data/ und .env in ${ARCHIVE}"
tar -czf "${STAGING_DIR}/${ARCHIVE}" -C "${REPO_ROOT}" data .env

echo "==> Verschluessele mit age"
age -r "${AGE_RECIPIENT}" -o "${STAGING_DIR}/${ENCRYPTED}" "${STAGING_DIR}/${ARCHIVE}"
rm -f "${STAGING_DIR}/${ARCHIVE}"

echo "==> Lade nach ${BACKUP_REMOTE} hoch"
rclone copy "${STAGING_DIR}/${ENCRYPTED}" "${BACKUP_REMOTE}"

echo "==> Rotation anwenden (${BACKUP_RETENTION_DAILY} taeglich, ${BACKUP_RETENTION_WEEKLY} woechentlich)"

# Alle vorhandenen Backups (Dateiname traegt das Datum), neueste zuerst.
mapfile -t ALL_BACKUPS < <(rclone lsf "${BACKUP_REMOTE}" --files-only | grep -E '^backup-[0-9]{4}-[0-9]{2}-[0-9]{2}\.tar\.gz\.age$' | sort -r)

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
    rclone deletefile "${BACKUP_REMOTE}/${f}"
  fi
done

echo "==> Backup abgeschlossen: ${ENCRYPTED} (behalten: ${#KEEP[@]} von ${#ALL_BACKUPS[@]})"
