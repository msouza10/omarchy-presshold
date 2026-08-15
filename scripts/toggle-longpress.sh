#!/bin/bash
# Idempotently enable/disable Fcitx5's native press-and-hold (EnableLongPress)
# in ~/.config/fcitx5/conf/keyboard.conf without touching any other key, then
# restart the Fcitx5 process so the new value actually takes effect.
#
# `fcitx5-remote -r` only reloads and was observed to NOT pick up a changed
# EnableLongPress value; a real process restart (`fcitx5 -r`) is required.
#
# Enabling also defaults "Choose Modifier" to None: Fcitx5's keyboard engine
# only treats 1-9 as candidate-select keys while that modifier is held (it
# defaults to Alt), so without this a bare number press falls through and
# gets typed into the field instead of picking a candidate — macOS-style
# press-and-hold expects plain number presses to select.

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

set_key() {
  local key="$1" value="$2"
  mkdir -p "$CONF_DIR"
  touch "$CONF"
  if grep -qF "$key=" "$CONF"; then
    sed -i "s|^$key=.*|$key=$value|" "$CONF"
  else
    printf '%s=%s\n' "$key" "$value" >>"$CONF"
  fi
}

restart_fcitx() {
  fcitx5 -r --disable notificationitem >/dev/null 2>&1 &
  disown
}

case "${1:-}" in
enable)
  set_key "EnableLongPress" "True"
  set_key "Choose Modifier" "None"
  restart_fcitx
  echo enabled
  ;;
disable)
  set_key "EnableLongPress" "False"
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
