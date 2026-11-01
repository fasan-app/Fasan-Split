#!/usr/bin/env bash
# Legt den Ordner logs/ als einzelnen Commit in einen Log-Branch (überschreibt ihn).
# Aufruf: push-logs.sh "<stand>" [branch]; Standard ci-logs, der Emulator-Job nutzt ci-logs-emulator.
# So sind Build-Logs lesbar, ohne die Actions-Oberfläche zu öffnen.
set -u
BRANCH="${2:-ci-logs}"
mkdir -p logs
cd logs
{
  echo "commit: ${GITHUB_SHA}"
  echo "lauf: ${GITHUB_RUN_NUMBER}"
  echo "stand: $1"
  date -u +"zeit: %Y-%m-%dT%H:%M:%SZ"
} > status.txt
rm -rf .git
git init -q
git config user.name "Fasan CI"
git config user.email "ci@users.noreply.github.com"
git add -A
git commit -qm "Logs Lauf ${GITHUB_RUN_NUMBER}: $1"
git push -qf "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:${BRANCH}"
rm -rf .git
