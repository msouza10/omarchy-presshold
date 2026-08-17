#!/bin/bash
# Idempotently enable/disable Fcitx5's native press-and-hold (EnableLongPress)
# without touching any other setting.
#
# The change is applied through Fcitx5's own D-Bus config API
# (scripts/fcitx5_config.py), not by sed'ing ~/.config/fcitx5/conf/keyboard.conf
# behind its back. Fcitx5 owns that file while it runs: it rewrites it from its
# in-memory state on a periodic autosave and again on shutdown -- including the
# shutdown half of the `systemctl restart` this script used to run to apply the
# edit. An edit racing that save is silently reverted whenever it loses, which
# is why the toggle appeared to work only sometimes. SetConfig updates the live
# process, which then persists the file itself: no race, and no restart needed
# at all (`fcitx5-remote -r` was what didn't pick up a changed EnableLongPress;
# SetConfig does, since it goes through the addon's own setConfig path).
#
# Editing the file directly is still correct when Fcitx5 is not running (the
# helper exits 3): nothing is up to overwrite it, and Fcitx5 reads it on its
# next start. That path restarts the service once, at the end, so an enable
# that also installs the theme hook never restarts twice in a row -- back-to-back
# restarts leave a window with no input method bound (the Wayland handshake
# takes ~10s) and can trip the unit's StartLimitBurst.
#
# On a stock Omarchy install, Fcitx5 runs under systemd (`omarchy-fcitx5.service`,
# Restart=always). Restarting by spawning a detached `fcitx5 -r &` process steals
# its D-Bus name out from under it: the systemd-managed process then fails to
# (re)acquire that name, exits, and gets restarted by systemd, forever -- a
# silent, fast crash-loop that leaves the detached orphan as the only live
# instance. `systemctl --user restart` is the only method that doesn't fight the
# service manager. Fall back to the direct replace only when the unit isn't
# present at all.
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
HELPER="$SCRIPT_DIR/fcitx5_config.py"
THEME_HOOK_SOURCE="$PLUGIN_DIR/extras/theme-set.d/fcitx5-theme.sh"
THEME_HOOK_DEST="$HOME/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh"

# Exit code the helper uses for "Fcitx5 isn't reachable on the session bus".
FCITX_UNAVAILABLE=3

# Set by apply_keys when it had to fall back to editing the file, so the
# caller can restart Fcitx5 exactly once, at the end.
NEEDS_RESTART=0

set_key() {
  local key="$1" value="$2"
  mkdir -p "$CONF_DIR"
  touch "$CONF"
  if grep -q "^$key=" "$CONF"; then
    sed -i "s|^$key=.*|$key=$value|" "$CONF"
  else
    printf '%s=%s\n' "$key" "$value" >>"$CONF"
  fi
}

status() {
  local value rc=0
  value=$(python3 "$HELPER" get keyboard EnableLongPress 2>/dev/null) || rc=$?
  if [[ $rc -ne 0 ]]; then
    # Fcitx5 is down, so the file is the only source of truth -- and an
    # authoritative one, since nothing is running to have diverged from it.
    if [[ -f "$CONF" ]] && grep -q '^EnableLongPress=True' "$CONF"; then
      value=True
    else
      value=False
    fi
  fi

  if [[ "$value" == "True" ]]; then
    echo enabled
  else
    echo disabled
  fi
}

# apply_keys <key>=<value>...
apply_keys() {
  local rc=0
  python3 "$HELPER" set keyboard "$@" || rc=$?

  case $rc in
  0) ;;
  "$FCITX_UNAVAILABLE")
    local pair
    for pair in "$@"; do
      set_key "${pair%%=*}" "${pair#*=}"
    done
    NEEDS_RESTART=1
    ;;
  *)
    exit $rc
    ;;
  esac
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
# restarts Fcitx5 itself after generating the theme (the theme *name* doesn't
# change, only the PNGs behind it, and a running ClassicUI keeps the images it
# already loaded), so callers must skip their own restart when this succeeds.
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
  apply_keys "EnableLongPress=True" "Choose Modifier=None"
  if install_theme_hook_if_missing; then
    NEEDS_RESTART=0
  fi
  if [[ $NEEDS_RESTART -eq 1 ]]; then
    restart_fcitx
  fi
  echo enabled
  ;;
disable)
  apply_keys "EnableLongPress=False"
  if [[ $NEEDS_RESTART -eq 1 ]]; then
    restart_fcitx
  fi
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
