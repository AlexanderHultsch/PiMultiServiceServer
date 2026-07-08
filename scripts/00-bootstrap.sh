#!/usr/bin/env bash
# Schritt 2 der SPEC (Abschnitt 7.1): OS-Update, Basis-Pakete, Docker.
# Idempotent: kann gefahrlos mehrfach ausgefuehrt werden.
set -euo pipefail

echo "==> System aktualisieren"
sudo apt update && sudo apt full-upgrade -y

echo "==> Basis-Pakete installieren"
sudo apt install -y ufw fail2ban unattended-upgrades rclone age

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Docker installieren"
  curl -fsSL https://get.docker.com | sh
else
  echo "==> Docker bereits installiert, ueberspringe"
fi

if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  echo "==> '$USER' zur docker-Gruppe hinzugefuegt"
fi

sudo dpkg-reconfigure -plow unattended-upgrades

echo "Bootstrap fertig. Bitte neu einloggen (Docker-Gruppe), falls gerade hinzugefuegt."
