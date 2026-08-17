#!/bin/bash
# Undo everything this plugin ever wrote outside its own folder, so that
# `omarchy plugin remove` afterwards leaves nothing behind.
#
# Run this BEFORE removing the plugin. Omarchy's plugin manifest has no
# uninstall hook -- `omarchy plugin remove` disables the plugin in the shell,
# deletes (or backs up) the folder and rescans, and there is no point at which
# it can call into the plugin being removed. So this cannot be automatic. What
# it can be is one command that does the whole job exactly, instead of a list
# of manual steps in a README.
#
# What it reverts, in order:
#   1. The keyboard engine keys, back to the values recorded before the first
#      enable (scripts/toggle-longpress.sh disable does that part).
#   2. The ClassicUI popup keys, back to what the theme hook recorded before it
#      first ran.
#   3. The generated Fcitx5 theme and the theme-set.d hook that regenerates it
#      -- an orphaned hook would keep rebuilding a theme for a plugin that no
#      longer exists, on every `omarchy theme set`.
#   4. The state directory holding those two records.
#
# What it deliberately leaves alone: Fcitx5 itself, its service, and every
# setting this plugin never wrote. The long-press candidate *order* set through
# the keyboard picker stays too -- it is Fcitx5's own data, it remains
# meaningful without this plugin, and there is no "before" recorded to return
# it to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HELPER="$SCRIPT_DIR/fcitx5_config.py"
TOGGLE="$SCRIPT_DIR/toggle-longpress.sh"
THEME_HOOK_SOURCE="$PLUGIN_DIR/extras/theme-set.d/fcitx5-theme.sh"
THEME_HOOK_DEST="$HOME/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh"
FCITX_THEME_DIR="$HOME/.local/share/fcitx5/themes/omarchy"
CLASSICUI_CONF="$HOME/.config/fcitx5/conf/classicui.conf"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omaccerts.presshold"
KEYBOARD_SNAPSHOT="$STATE_DIR/keyboard-before.conf"
CLASSICUI_SNAPSHOT="$STATE_DIR/classicui-before.conf"

# Fcitx5's own defaults for the ClassicUI keys the theme hook writes. Used for
# any key the snapshot recorded as empty: it wasn't set before the hook ran, so
# putting the default back amounts to never having set it.
default_classicui() {
  case "$1" in
  "Theme") printf 'default' ;;
  "DarkTheme") printf 'default-dark' ;;
  "UseDarkTheme") printf 'True' ;;
  "UseAccentColor") printf 'True' ;;
  "Font" | "MenuFont") printf 'Sans 10' ;;
  *) printf '' ;;
  esac
}

# 1. Keyboard engine keys. The toggle owns that snapshot and already restores
#    every key it manages, so the logic isn't duplicated here.
if [[ -f "$TOGGLE" ]]; then
  bash "$TOGGLE" disable >/dev/null
  echo "Restored the keyboard engine's long-press settings."
else
  echo "warning: $TOGGLE is missing; left the keyboard settings alone." >&2
fi

# 2. ClassicUI popup keys.
if [[ -f "$CLASSICUI_SNAPSHOT" ]]; then
  pairs=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -n "$value" ]] || value=$(default_classicui "$key")
    pairs+=("$key=$value")
  done <"$CLASSICUI_SNAPSHOT"

  if ((${#pairs[@]} > 0)); then
    rc=0
    python3 "$HELPER" set classicui "${pairs[@]}" || rc=$?
    if [[ $rc -ne 0 ]]; then
      # Fcitx5 is down (or python-dbus is gone): editing the file is safe for
      # exactly that reason -- the same fallback the rest of the plugin uses.
      mkdir -p "$(dirname "$CLASSICUI_CONF")"
      touch "$CLASSICUI_CONF"
      for pair in "${pairs[@]}"; do
        key="${pair%%=*}"
        if grep -q "^$key=" "$CLASSICUI_CONF"; then
          sed -i "s|^$key=.*|$pair|" "$CLASSICUI_CONF"
        else
          printf '%s\n' "$pair" >>"$CLASSICUI_CONF"
        fi
      done
    fi
    echo "Restored the candidate popup's ClassicUI settings."
  fi
else
  echo "No ClassicUI snapshot found — the theme hook never ran, so there is nothing to restore."
fi

# 3. The theme-set.d hook and the theme it generates.
#
# The hook is only deleted while it still matches the copy this plugin ships.
# It is installed under a "never overwrite what's already there" rule, and
# deleting a version someone has since edited would throw away their work --
# the same rule, in the other direction.
if [[ -f "$THEME_HOOK_DEST" ]]; then
  if [[ -f "$THEME_HOOK_SOURCE" ]] && cmp -s "$THEME_HOOK_SOURCE" "$THEME_HOOK_DEST"; then
    rm -f "$THEME_HOOK_DEST"
    echo "Removed the theme-set.d hook."
  else
    echo "Kept $THEME_HOOK_DEST — it differs from the shipped copy, so it looks hand-edited."
    echo "  It will keep regenerating the Fcitx5 theme on every theme change; delete it yourself if you don't want that."
  fi
fi

if [[ -d "$FCITX_THEME_DIR" ]]; then
  rm -rf "$FCITX_THEME_DIR"
  echo "Removed the generated Fcitx5 theme."
fi

# 4. The records themselves: only the two files this plugin wrote, and the
#    directory only when that leaves it empty. Never a blind recursive delete
#    of a directory under the user's state dir.
rm -f "$KEYBOARD_SNAPSHOT" "$CLASSICUI_SNAPSHOT"
rmdir "$STATE_DIR" 2>/dev/null || true

echo
echo "Done. You can remove the plugin now:"
echo "  omarchy plugin remove omaccerts.presshold --yes"
