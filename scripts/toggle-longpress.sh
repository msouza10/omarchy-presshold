#!/bin/bash
# Idempotently enable/disable Fcitx5's native press-and-hold (EnableLongPress)
# in ~/.config/fcitx5/conf/keyboard.conf without touching any other key, then
# restart the Fcitx5 process so the new value actually takes effect.
#
# `fcitx5-remote -r` only reloads and was observed to NOT pick up a changed
# EnableLongPress value; a real process restart is required. On a stock
# Omarchy install, Fcitx5 runs under systemd (`omarchy-fcitx5.service`,
# Restart=always). Restarting by spawning a detached `fcitx5 -r &` process
# steals its D-Bus name out from under it: the systemd-managed process then
# fails to (re)acquire that name, exits, and gets restarted by systemd,
# forever — a silent, fast crash-loop that leaves the detached orphan as the
# only live instance. `systemctl --user restart` is the only method that
# doesn't fight the service manager. Fall back to the direct replace only
# when the unit isn't present at all.
#
# Enabling also defaults "Choose Modifier" to None: Fcitx5's keyboard engine
# only treats 1-9 as candidate-select keys while that modifier is held (it
# defaults to Alt), so without this a bare number press falls through and
# gets typed into the field instead of picking a candidate — macOS-style
# press-and-hold expects plain number presses to select.
#
# scripts/reorder-candidates.py (separate script) reorders which candidate
# comes first for a given key -- e.g. promoting "ã" ahead of "à" for "a" --
# rather than which keys get long-press at all, which is this script's job.

set -euo pipefail

CONF_DIR="$HOME/.config/fcitx5/conf"
CONF="$CONF_DIR/keyboard.conf"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
THEME_HOOK_SOURCE="$PLUGIN_DIR/extras/theme-set.d/fcitx5-theme.sh"
THEME_HOOK_DEST="$HOME/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh"

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
  if systemctl --user list-unit-files omarchy-fcitx5.service >/dev/null 2>&1; then
    systemctl --user restart omarchy-fcitx5.service
  else
    fcitx5 -r --disable notificationitem >/dev/null 2>&1 &
    disown
  fi
}

# One-time install of the optional theme-matching hook (extras/theme-set.d),
# run the first time someone enables Press & Hold. Only touches the hook if
# nothing is there yet, so it never overwrites a hand-edited copy. The hook
# restarts Fcitx5 itself after generating the theme, so callers should skip
# their own restart_fcitx when this returns success.
install_theme_hook_if_missing() {
  [[ -f "$THEME_HOOK_SOURCE" ]] || return 1
  [[ -f "$THEME_HOOK_DEST" ]] && return 1
  mkdir -p "$(dirname "$THEME_HOOK_DEST")"
  cp "$THEME_HOOK_SOURCE" "$THEME_HOOK_DEST"
  chmod +x "$THEME_HOOK_DEST"
  bash "$THEME_HOOK_DEST"
}

case "${1:-}" in
enable)
  set_key "EnableLongPress" "True"
  set_key "Choose Modifier" "None"
  if ! install_theme_hook_if_missing; then
    restart_fcitx
  fi
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
