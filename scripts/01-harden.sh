#!/usr/bin/env bash
# Schritt 3 der SPEC (Abschnitt 7.2): SSH-Haertung + ufw Default-Deny.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
set -a; source "${REPO_ROOT}/.env"; set +a

: "${LAN_SUBNET:?LAN_SUBNET fehlt in .env}"
: "${PORT_DNS:?PORT_DNS fehlt in .env}"
: "${PORT_PIHOLE_UI:?PORT_PIHOLE_UI fehlt in .env}"
: "${PORT_UPTIME:?PORT_UPTIME fehlt in .env}"

AUTH_KEYS="${HOME}/.ssh/authorized_keys"
if [[ ! -s "${AUTH_KEYS}" ]]; then
  echo "FEHLER: ${AUTH_KEYS} ist leer oder existiert nicht." >&2
  echo "Bevor Passwort-Login deaktiviert wird, muss dein SSH-Public-Key dort hinterlegt sein," >&2
  echo "sonst sperrst du dich selbst aus. Siehe README Abschnitt 'SSH-Zugriff einrichten'." >&2
  exit 1
fi

echo "==> SSH-Haertung (Public-Key-only, kein Root-Login)"
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

echo "==> Firewall: Default-Deny eingehend, Zugriff nur aus ${LAN_SUBNET}"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from "${LAN_SUBNET}" to any port 22 proto tcp
sudo ufw allow from "${LAN_SUBNET}" to any port "${PORT_DNS}" proto tcp
sudo ufw allow from "${LAN_SUBNET}" to any port "${PORT_DNS}" proto udp
sudo ufw allow from "${LAN_SUBNET}" to any port "${PORT_PIHOLE_UI}" proto tcp
sudo ufw allow from "${LAN_SUBNET}" to any port "${PORT_UPTIME}" proto tcp
sudo ufw --force enable

echo "==> Haertung abgeschlossen. Pruefen mit: sudo ufw status verbose"
