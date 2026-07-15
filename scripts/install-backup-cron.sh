#!/usr/bin/env bash
# Traegt den naechtlichen Backup-Job idempotent in die ROOT-crontab ein (SPEC 8.2.6).
# Root-crontab, weil backup.sh root-Rechte braucht (Begruendung siehe backup.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${REPO_ROOT}/backup.log"
CRON_CMD="cd ${REPO_ROOT} && ./scripts/backup.sh >> ${LOG_FILE} 2>&1"
CRON_LINE="0 3 * * * ${CRON_CMD}"

# Aufraeumen: fruehere Versionen dieses Skripts haben den Job in die
# NUTZER-crontab eingetragen - dort wuerde er mangels root-Rechten
# fehlschlagen. Falls vorhanden, entfernen.
if crontab -l 2>/dev/null | grep -qF "${CRON_CMD}"; then
  crontab -l 2>/dev/null | grep -vF "${CRON_CMD}" | crontab -
  echo "Veralteten Eintrag aus der Nutzer-crontab entfernt."
fi

if sudo crontab -l 2>/dev/null | grep -qF "${CRON_CMD}"; then
  echo "Cron-Job existiert bereits in der root-crontab, keine Aenderung noetig:"
  sudo crontab -l | grep -F "${CRON_CMD}"
else
  (sudo crontab -l 2>/dev/null; echo "${CRON_LINE}") | sudo crontab -
  echo "Cron-Job installiert (root-crontab, taeglich 03:00 Uhr):"
  echo "${CRON_LINE}"
fi

echo "Log-Datei: ${LOG_FILE}"
