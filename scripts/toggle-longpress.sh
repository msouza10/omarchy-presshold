#!/bin/bash
# Idempotently enable/disable Fcitx5's native press-and-hold (EnableLongPress)
# in ~/.config/fcitx5/conf/keyboard.conf without touching any other key, then
# restart the Fcitx5 process so the new value actually takes effect.
#
# `fcitx5-remote -r` only reloads and was observed to NOT pick up a changed
# EnableLongPress value; a real process restart (`fcitx5 -r`) is required.

set -euo pipefail

CONF_DIR="$HOME/.config/fcitx5/conf"
CONF="$CONF_DIR/keyboard.conf"

status() {
  if [[ -f "$CONF" ]] && grep -q '^EnableLongPress=True' "$CONF"; then
    echo enabled
  else
    echo disabled
  fi
}

set_value() {
  local value="$1"
  mkdir -p "$CONF_DIR"
  touch "$CONF"
  if grep -q '^EnableLongPress=' "$CONF"; then
    sed -i "s/^EnableLongPress=.*/EnableLongPress=$value/" "$CONF"
  else
    printf 'EnableLongPress=%s\n' "$value" >>"$CONF"
  fi
}

restart_fcitx() {
  fcitx5 -r --disable notificationitem >/dev/null 2>&1 &
  disown
}

case "${1:-}" in
enable)
  set_value True
  restart_fcitx
  echo enabled
  ;;
disable)
  set_value False
  restart_fcitx
  echo disabled
  ;;
status)
  status
  ;;
*)
  echo "usage: $0 {enable|disable|status}" >&2
  exit 1
  ;;
esac
