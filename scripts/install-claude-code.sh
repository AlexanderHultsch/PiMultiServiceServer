#!/usr/bin/env bash
# Installiert die Claude Code CLI fuer On-Demand-Debugging direkt auf dem Pi.
# Richtet KEINEN Hintergrunddienst ein - die CLI wird nur bei Bedarf manuell
# mit 'claude' aufgerufen (siehe README "Claude Code direkt auf dem Pi").
set -euo pipefail

NEED_NODE=1
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
  if [[ "${NODE_MAJOR}" -ge 18 ]]; then
    NEED_NODE=0
  fi
fi

if [[ "${NEED_NODE}" -eq 1 ]]; then
  echo "==> Node.js (LTS) installieren (Voraussetzung fuer die Claude Code CLI)"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
  sudo apt install -y nodejs
else
  echo "==> Node.js $(node --version) bereits ausreichend, ueberspringe Installation"
fi

echo "==> Claude Code CLI installieren (per npm)"
# Bewusst npm statt nativem Installer (curl -fsSL https://claude.ai/install.sh | bash):
# der native Installer hat auf ARM64/Raspberry Pi bekannte Probleme (meldet Erfolg,
# installiert die Binary aber nicht mit) - siehe README fuer Details/Quelle.
sudo npm install -g @anthropic-ai/claude-code

echo
echo "=================================================================="
echo "Installation abgeschlossen. Es laeuft kein Hintergrunddienst -"
echo "die CLI wird nur bei Bedarf manuell mit 'claude' im Projektordner"
echo "gestartet und beendet sich wieder, sobald du fertig bist."
echo
echo "Falls oben eine Warnung 'npm warn allow-scripts ... not yet covered'"
echo "erschien: mit 'claude --version' pruefen, ob es trotzdem funktioniert"
echo "(sollte eine Versionsnummer ausgeben). Falls nicht:"
echo "  npm approve-scripts --allow-scripts-pending"
echo
echo "Naechster Schritt: einmalig anmelden - VORHER dauerhaft setzen, damit"
echo "das interaktive Anmelde-Menue beim ersten 'claude'-Aufruf entfaellt:"
echo "  1) API-Key:"
echo "       echo 'export ANTHROPIC_API_KEY=<dein-api-key>' >> ~/.bashrc"
echo "       source ~/.bashrc"
echo "  2) Claude Pro/Max (Token auf einem Geraet MIT Browser erzeugen):"
echo "       claude setup-token"
echo "     Danach auf dem Pi:"
echo "       echo 'export CLAUDE_CODE_OAUTH_TOKEN=<token>' >> ~/.bashrc"
echo "       source ~/.bashrc"
echo "Details: README Abschnitt 'Claude Code direkt auf dem Pi'."
echo "=================================================================="
