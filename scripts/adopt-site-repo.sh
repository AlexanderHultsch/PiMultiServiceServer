#!/usr/bin/env bash
# Ersetzt eine im Haupt-Repo mitgelieferte Seite/App (z. B. das
# Beispiel-sites/main) durch einen eigenen, separaten Git-Klon - und traegt
# den Pfad automatisch in die .gitignore des Haupt-Repos ein, damit sich
# beide Repos nicht in die Quere kommen.
#
# Nutzung:  bash scripts/adopt-site-repo.sh <sites/name|apps/name> <git-url>
# Beispiel: bash scripts/adopt-site-repo.sh sites/main https://github.com/<du>/meine-homepage.git
#
# Hintergrund (der Fehler, den dieses Skript verhindert): Bleibt der Ordner
# Teil des Haupt-Repos, loest sich ein `git pull` darin still auf den REMOTE
# DES HAUPT-REPOS auf - nicht auf die eigentliche Website. Das Ergebnis ist
# ein taeuschendes "Already up to date", obwohl die Seite nie aktualisiert
# wird. Siehe README "Jede Seite als eigenes Git-Repo".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"
GIT_URL="${2:-}"

if [[ -z "${TARGET}" || -z "${GIT_URL}" ]]; then
  echo "Nutzung: bash scripts/adopt-site-repo.sh <sites/name|apps/name> <git-url>" >&2
  exit 1
fi

DIR="${REPO_ROOT}/${TARGET}"

if [[ ! -d "${DIR}" ]]; then
  echo "FEHLER: ${DIR} existiert nicht." >&2
  exit 1
fi

# Wichtig: "git -C DIR rev-parse --git-dir" alleine reicht nicht als Check -
# es findet auch das .git des Haupt-Repos in einem Elternordner und meldet
# faelschlich Erfolg (genau der Bug, den dieses Skript beheben soll). Statt-
# dessen pruefen, ob DIR selbst die Repo-Wurzel ist.
TOPLEVEL="$(git -C "${DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "${TOPLEVEL}" && "$(cd "${DIR}" && pwd -P)" == "$(cd "${TOPLEVEL}" && pwd -P)" ]]; then
  echo "FEHLER: ${DIR} ist bereits ein eigenes Git-Repo - nichts zu tun." >&2
  exit 1
fi

cd "${REPO_ROOT}"

echo "==> Entferne ${TARGET} aus der Versionsverwaltung des Haupt-Repos (Dateien bleiben vorerst liegen)"
git rm -r --cached "${TARGET}" >/dev/null

if ! grep -qxF "/${TARGET}/" .gitignore 2>/dev/null; then
  echo "/${TARGET}/" >> .gitignore
  git add .gitignore
  echo "==> /${TARGET}/ zur .gitignore hinzugefuegt"
fi

git commit -m "Haupt-Repo: ${TARGET} ignorieren (jetzt eigenes Git-Repo)" >/dev/null
echo "==> Commit im Haupt-Repo erstellt - nicht vergessen, ihn zu pushen (git push)"

BACKUP_DIR="${DIR}.bak-$(date +%Y%m%d%H%M%S)"
echo "==> Alten Inhalt nach ${BACKUP_DIR} verschoben, dann frischer Klon von ${GIT_URL}"
mv "${DIR}" "${BACKUP_DIR}"
git clone "${GIT_URL}" "${DIR}"

echo "==> Fertig. ${TARGET} ist jetzt ein eigenes Git-Repo (Klon von ${GIT_URL})."
echo "    Alter Inhalt liegt zur Kontrolle in ${BACKUP_DIR} - danach manuell loeschen:"
echo "      rm -rf ${BACKUP_DIR}"
echo "    Aktualisieren kuenftig per: bash scripts/deploy-site.sh $(basename "${TARGET}")"
