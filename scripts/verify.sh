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
check_static_ip_bound() {
  # Erkennt Drift zwischen .env und der tatsaechlich aktiven Netzwerk-IP
  # (z.B. falsches Interface im Router reserviert, oder WLAN/LAN vertauscht).
  [[ -f .env ]] || return 1
  # shellcheck disable=SC1091
  set -a; source .env; set +a
  [[ -n "${PI_STATIC_IP:-}" ]] || return 1
  ip -4 addr show | grep -q "inet ${PI_STATIC_IP}/"
}
check_wifi_not_unexpectedly_blocked() {
  # Warnt, falls WLAN per rfkill blockiert ist, OBWOHL kein Ethernet-Kabel
  # aktiv ist - das wuerde den Pi komplett vom Netz trennen (siehe README
  # Troubleshooting "Nach Neustart keine Verbindung mehr, WLAN tot").
  command -v rfkill >/dev/null 2>&1 || return 0
  rfkill list wifi 2>/dev/null | grep -qi "Soft blocked: yes" || return 0
  ip -4 addr show eth0 2>/dev/null | grep -q "inet " && return 0
  return 1
}

check "docker compose config ist gueltig" check_compose_config
check "Alle Compose-Dienste laufen" check_compose_running
check "Keine Secrets/data/ im Git" check_no_secrets_in_git
check "ufw: aktiv + Default-Deny eingehend" check_ufw_default_deny
check "Oeffentliche Webseite unter https://\${DOMAIN} erreichbar" check_domain_reachable
check "PI_STATIC_IP ist tatsaechlich an einem Interface aktiv" check_static_ip_bound
check "WLAN nicht blockiert, waehrend kein Ethernet aktiv ist" check_wifi_not_unexpectedly_blocked

echo "=================================================================="
echo "Ergebnis: ${PASS} bestanden, ${FAIL} fehlgeschlagen"
echo "=================================================================="
[[ "${FAIL}" -eq 0 ]]
