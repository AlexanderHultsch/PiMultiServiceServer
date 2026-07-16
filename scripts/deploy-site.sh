#!/usr/bin/env bash
# Aktualisiert eine einzelne Website auf den neuesten Stand ihres Git-Repos.
# Nutzung:  bash scripts/deploy-site.sh <name>
#
# Findet den Ordner automatisch:
#   sites/<name>/  -> statische Seite: git pull genuegt (Caddy liefert live aus)
#   apps/<name>/   -> dynamische App: git pull + Container neu bauen/starten
#
# Voraussetzung: Der jeweilige Ordner ist ein eigenes Git-Repo (siehe README
# "Weitere Websites hosten"). Ist es KEIN Git-Repo (z.B. die mitgelieferten
# Beispiele, die im Haupt-Repo liegen), wird der git-pull-Schritt uebersprungen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

NAME="${1:-}"
if [[ -z "${NAME}" ]]; then
  echo "Nutzung: bash scripts/deploy-site.sh <name>" >&2
  echo "Vorhandene Seiten:" >&2
  ls -1 "${REPO_ROOT}/sites" 2>/dev/null | sed 's/^/  sites\//' >&2 || true
  ls -1 "${REPO_ROOT}/apps" 2>/dev/null | sed 's/^/  apps\//' >&2 || true
  exit 1
fi

pull_if_git_repo() {
  local dir="$1"
  if git -C "${dir}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "==> git pull in ${dir}"
    git -C "${dir}" pull --ff-only
  else
    echo "==> ${dir} ist kein eigenes Git-Repo - ueberspringe git pull"
    echo "    (Aenderungen liegen direkt im Haupt-Repo, dort committen/pullen.)"
  fi
}

if [[ -d "${REPO_ROOT}/apps/${NAME}" ]]; then
  pull_if_git_repo "${REPO_ROOT}/apps/${NAME}"
  echo "==> Dynamische App neu bauen und starten: ${NAME}"
  docker compose -f "${REPO_ROOT}/docker-compose.yml" up -d --build "${NAME}"
elif [[ -d "${REPO_ROOT}/sites/${NAME}" ]]; then
  pull_if_git_repo "${REPO_ROOT}/sites/${NAME}"
  echo "==> Statische Seite '${NAME}' aktualisiert - Caddy liefert die Dateien"
  echo "    live aus, kein Neustart noetig."
else
  echo "FEHLER: weder sites/${NAME} noch apps/${NAME} gefunden." >&2
  exit 1
fi

echo "==> Fertig."
