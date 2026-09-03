#!/bin/zsh
# Starts NotesMD whenever Apple Notes is running.
# $1 = path to NotesMD.app

set -u
APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  exit 0
fi

SUPPORT="${HOME}/Library/Application Support/NotesMD"
SKIP="${SUPPORT}/skip-autolaunch"
mkdir -p "$SUPPORT"

while true; do
  if pgrep -xq Notes; then
    if [[ ! -f "$SKIP" ]] && ! pgrep -xq NotesMD; then
      open -gj -a "$APP" >/dev/null 2>&1 || true
    fi
  else
    rm -f "$SKIP"
  fi
  sleep 2
done
