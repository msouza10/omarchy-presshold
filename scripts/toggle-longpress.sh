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

# Where the pre-plugin value of every key this script manages is recorded, so
# `disable` can put them back rather than merely switching long-press off.
#
# Lives outside the plugin directory on purpose: `omarchy plugin remove`
# deletes the plugin folder, and a record of what to undo is worth nothing if
# it goes with it.
#
# Only the managed keys are recorded, not a copy of the whole keyboard.conf.
# Restoring a whole-file backup would also roll back any unrelated Fcitx5
# setting the user changed in the meantime, which is exactly the kind of
# collateral damage the rest of this plugin goes out of its way to avoid.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/io.github.msouza10.presshold"
SNAPSHOT="$STATE_DIR/keyboard-before.conf"

# The only keys this plugin ever writes in the keyboard engine's config, with
# Fcitx5's own default for each. The defaults are the last resort for taking a
# snapshot while Fcitx5 is down and the key is not in the file yet.
MANAGED_KEYS=("EnableLongPress" "Choose Modifier")
DEFAULT_ENABLE_LONG_PRESS="False"
DEFAULT_CHOOSE_MODIFIER="Alt"

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

default_for() {
  case "$1" in
  "EnableLongPress") printf '%s' "$DEFAULT_ENABLE_LONG_PRESS" ;;
  "Choose Modifier") printf '%s' "$DEFAULT_CHOOSE_MODIFIER" ;;
  *) printf '' ;;
  esac
}

# Current value of one managed key, asking the live Fcitx5 first and falling
# back to the file, then to Fcitx5's default. GetConfig always answers with the
# effective value (the default when nothing is set), so a snapshot taken this
# way is well defined even on a config that has never been touched.
current_value() {
  local key="$1" value rc=0
  value=$(python3 "$HELPER" get keyboard "$key" 2>/dev/null) || rc=$?
  if [[ $rc -eq 0 && -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi
  if [[ -f "$CONF" ]] && grep -q "^$key=" "$CONF"; then
    sed -n "s|^$key=||p" "$CONF" | head -1 | tr -d '\r'
    return 0
  fi
  default_for "$key"
}

# Record what the managed keys looked like before this plugin first changed
# them. Written once and never overwritten: the first snapshot is the only
# pristine one, and re-taking it after an enable would capture our own values
# and make `disable` a no-op.
save_snapshot() {
  [[ -f "$SNAPSHOT" ]] && return 0
  mkdir -p "$STATE_DIR"
  local key tmp="$SNAPSHOT.tmp"
  : >"$tmp"
  for key in "${MANAGED_KEYS[@]}"; do
    printf '%s=%s\n' "$key" "$(current_value "$key")" >>"$tmp"
  done
  mv "$tmp" "$SNAPSHOT"
}

# The values `disable` should put back: the snapshot when there is one, else
# Fcitx5's defaults (the plugin was enabled before this existed, or someone
# removed the state file).
restore_pairs() {
  local key value
  for key in "${MANAGED_KEYS[@]}"; do
    value=""
    if [[ -f "$SNAPSHOT" ]] && grep -q "^$key=" "$SNAPSHOT"; then
      value=$(sed -n "s|^$key=||p" "$SNAPSHOT" | head -1 | tr -d '\r')
    fi
    [[ -n "$value" ]] || value=$(default_for "$key")
    printf '%s=%s\n' "$key" "$value"
  done
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
  # Snapshot before the first write, never after: this is the only moment the
  # pre-plugin values are still on disk.
  save_snapshot
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
  # A real undo, not just EnableLongPress=False: every managed key goes back
  # to what it was before the plugin first touched it, "Choose Modifier"
  # included. That is what makes turning the toggle off enough to leave
  # keyboard.conf as it was found -- `omarchy plugin remove` has no
  # uninstall hook to do it for us afterwards.
  mapfile -t pairs < <(restore_pairs)
  apply_keys "${pairs[@]}"
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
