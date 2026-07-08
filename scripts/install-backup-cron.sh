#!/usr/bin/env bash
# Traegt den naechtlichen Backup-Job idempotent in die crontab ein (SPEC 8.2.6).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${REPO_ROOT}/backup.log"
CRON_CMD="cd ${REPO_ROOT} && ./scripts/backup.sh >> ${LOG_FILE} 2>&1"
CRON_LINE="0 3 * * * ${CRON_CMD}"

if crontab -l 2>/dev/null | grep -qF "${CRON_CMD}"; then
  echo "Cron-Job existiert bereits, keine Aenderung noetig:"
  crontab -l | grep -F "${CRON_CMD}"
else
  (crontab -l 2>/dev/null; echo "${CRON_LINE}") | crontab -
  echo "Cron-Job installiert (taeglich 03:00 Uhr):"
  echo "${CRON_LINE}"
fi

echo "Log-Datei: ${LOG_FILE}"
