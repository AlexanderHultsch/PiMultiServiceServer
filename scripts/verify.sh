#!/usr/bin/env bash
# Fuehrt alle Verifikations-Checks aus README/CLAUDE.md gebuendelt aus.
# Bricht bei Fehlern NICHT ab, sondern zeigt am Ende eine PASS/FAIL-Uebersicht.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "${REPO_ROOT}"

PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  echo "--- ${desc} ---"
  if "$@"; then
    echo "PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${desc}"
    FAIL=$((FAIL + 1))
  fi
  echo
}

check_compose_config() { docker compose config >/dev/null; }
check_compose_running() {
  local down
  down="$(docker compose ps --services --filter 'status=running' | wc -l)"
  local total
  total="$(docker compose config --services | wc -l)"
  [[ "${down}" -eq "${total}" ]] && [[ "${total}" -gt 0 ]]
}
check_no_secrets_in_git() {
  ! git ls-files | grep -qE '(^|/)\.env$|^data/'
}
check_ufw_default_deny() {
  command -v ufw >/dev/null 2>&1 || return 1
  sudo ufw status verbose | grep -q "Status: active" &&
  sudo ufw status verbose | grep -q "Default: deny (incoming)"
}
check_domain_reachable() {
  [[ -f .env ]] || return 1
  # shellcheck disable=SC1091
  set -a; source .env; set +a
  [[ -n "${DOMAIN:-}" && "${DOMAIN}" != "<<DOMAIN>>" ]] || return 1
  curl -fsI --max-time 10 "https://${DOMAIN}" >/dev/null
}

check "docker compose config ist gueltig" check_compose_config
check "Alle Compose-Dienste laufen" check_compose_running
check "Keine Secrets/data/ im Git" check_no_secrets_in_git
check "ufw: aktiv + Default-Deny eingehend" check_ufw_default_deny
check "Oeffentliche Webseite unter https://\${DOMAIN} erreichbar" check_domain_reachable

echo "=================================================================="
echo "Ergebnis: ${PASS} bestanden, ${FAIL} fehlgeschlagen"
echo "=================================================================="
[[ "${FAIL}" -eq 0 ]]
