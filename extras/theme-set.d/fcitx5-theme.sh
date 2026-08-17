#!/bin/bash
# Regenerates a Fcitx5 ClassicUI theme ("omarchy") from the currently active
# Omarchy theme's semantic colors (omarchy-theme-color), so the press-and-hold
# candidate popup matches the rest of the desktop instead of Fcitx5's stock
# default/default-dark theme. Runs on every `omarchy theme set` via the
# theme-set.d hook contract; also safe to run manually.
#
# The config keys go in over D-Bus (see apply_classicui_config below), but a
# restart is still needed at the end: the theme *name* never changes here,
# only the PNGs behind it, and a running ClassicUI keeps the images it has
# already loaded. This is the only restart in the plugin -- the bar toggle
# applies its change live, so an enable that also installs this hook doesn't
# restart Fcitx5 twice in a row.
#
# Restarting via `systemctl --user restart omarchy-fcitx5.service` (not a
# detached `fcitx5 -r &`): Fcitx5 runs under that unit (Restart=always) on a
# stock Omarchy install. A detached replace process steals its D-Bus name,
# so the service's own process fails to reacquire it and gets endlessly
# restarted by systemd — a silent crash-loop.

set -euo pipefail

FCITX_THEME_DIR="$HOME/.local/share/fcitx5/themes/omarchy"
FCITX_CLASSICUI_CONF="$HOME/.config/fcitx5/conf/classicui.conf"

# Pre-hook values of the ClassicUI keys written below, recorded once so
# scripts/uninstall.sh can put them back. Kept outside both the plugin and this
# hook's own directory: either can be deleted, and the record has to outlive
# them to be worth anything.
CLASSICUI_SNAPSHOT="${XDG_STATE_HOME:-$HOME/.local/state}/omaccerts.presshold/classicui-before.conf"
SOURCE_ASSETS_DIR="/usr/share/fcitx5/themes/default-dark"

color() {
  omarchy-theme-color "$1" "$2" 2>/dev/null || echo "$2"
}

BACKGROUND=$(color background "#101315")
DARKER_BACKGROUND=$(color darker_background "#080a0b")
FOREGROUND=$(color foreground "#cacccc")
ACCENT=$(color accent "#798186")
MUTED=$(color muted "#4b4e55")

mkdir -p "$FCITX_THEME_DIR"
cp -f "$SOURCE_ASSETS_DIR"/*.png "$FCITX_THEME_DIR/" 2>/dev/null || true

# Rounded corners + drop shadow need real 9-patch PNGs (Fcitx5's
# Background/Highlight fields only take a flat Color when no Image is set),
# which needs ImageMagick. That's not an Omarchy dependency — only
# omarchy-theme-color is guaranteed present — so fall back to flat colors
# when `magick` isn't installed rather than failing outright.
if command -v magick >/dev/null 2>&1; then
  HAVE_MAGICK=1
else
  HAVE_MAGICK=0
fi

if [[ $HAVE_MAGICK -eq 1 ]]; then
  # Canvas is transparent; SHADOW_MARGIN is the strip of canvas reserved for
  # the shadow's blur falloff outside the visible rect, and also becomes the
  # theme.conf ShadowMargin so the renderer doesn't treat it as clickable
  # panel area.
  RADIUS=8
  BORDER=2
  SHADOW_MARGIN=8
  BG_CANVAS=64

  magick -size "${BG_CANVAS}x${BG_CANVAS}" xc:none \
    -fill black \
    -draw "roundrectangle $SHADOW_MARGIN,$((SHADOW_MARGIN + 4)) $((BG_CANVAS - SHADOW_MARGIN)),$((BG_CANVAS - SHADOW_MARGIN + 4)) $RADIUS,$RADIUS" \
    -channel A -evaluate multiply 0.35 +channel \
    -blur 0x6 \
    /tmp/fcitx5-theme-shadow.png

  magick -size "${BG_CANVAS}x${BG_CANVAS}" xc:none \
    -fill "$BACKGROUND" -stroke "$ACCENT" -strokewidth "$BORDER" \
    -draw "roundrectangle $SHADOW_MARGIN,$SHADOW_MARGIN $((BG_CANVAS - SHADOW_MARGIN)),$((BG_CANVAS - SHADOW_MARGIN)) $RADIUS,$RADIUS" \
    /tmp/fcitx5-theme-rect.png

  HL_RADIUS=6
  HL_MARGIN=8
  HL_CANVAS=32

  magick -size "${HL_CANVAS}x${HL_CANVAS}" xc:none \
    -fill "$ACCENT" \
    -draw "roundrectangle $HL_MARGIN,$HL_MARGIN $((HL_CANVAS - HL_MARGIN)),$((HL_CANVAS - HL_MARGIN)) $HL_RADIUS,$HL_RADIUS" \
    /tmp/fcitx5-theme-highlight.png

  magick /tmp/fcitx5-theme-shadow.png /tmp/fcitx5-theme-rect.png -composite "$FCITX_THEME_DIR/background.png"
  cp -f /tmp/fcitx5-theme-highlight.png "$FCITX_THEME_DIR/highlight.png"
  rm -f /tmp/fcitx5-theme-shadow.png /tmp/fcitx5-theme-rect.png /tmp/fcitx5-theme-highlight.png

  BG_MARGIN=$((SHADOW_MARGIN + RADIUS))

  BACKGROUND_SECTION="Image=background.png"
  HIGHLIGHT_SECTION="Image=highlight.png"
  TEXT_MARGIN=$((SHADOW_MARGIN + 2))
  TEXT_MARGIN_V=$((SHADOW_MARGIN + 1))
  CONTENT_MARGIN=$((SHADOW_MARGIN + 1))
  CONTENT_MARGIN_V=$SHADOW_MARGIN
else
  BORDER=2
  SHADOW_MARGIN=0
  BG_MARGIN=2
  HL_MARGIN=5

  BACKGROUND_SECTION="Color=$BACKGROUND
BorderColor=$ACCENT
BorderWidth=$BORDER"
  HIGHLIGHT_SECTION="Color=$ACCENT"
  TEXT_MARGIN=5
  TEXT_MARGIN_V=5
  CONTENT_MARGIN=2
  CONTENT_MARGIN_V=2
fi

cat >"$FCITX_THEME_DIR/theme.conf" <<THEMEEOF
[Metadata]
Name=Omarchy
Version=1
Author=omaccerts
Description=Generated from the active Omarchy theme's colors.toml
ScaleWithDPI=True

[InputPanel]
NormalColor=$FOREGROUND
HighlightCandidateColor=$DARKER_BACKGROUND
HighlightColor=$DARKER_BACKGROUND
HighlightBackgroundColor=$ACCENT
EnableBlur=True
PageButtonAlignment=Last Candidate

[InputPanel/BlurMargin]
Left=$SHADOW_MARGIN
Right=$SHADOW_MARGIN
Top=$SHADOW_MARGIN
Bottom=$SHADOW_MARGIN

[InputPanel/TextMargin]
Left=$TEXT_MARGIN
Right=$TEXT_MARGIN
Top=$TEXT_MARGIN_V
Bottom=$TEXT_MARGIN_V

[InputPanel/ContentMargin]
Left=$CONTENT_MARGIN
Right=$CONTENT_MARGIN
Top=$CONTENT_MARGIN_V
Bottom=$CONTENT_MARGIN_V

[InputPanel/Background]
$BACKGROUND_SECTION

[InputPanel/Background/Margin]
Left=$BG_MARGIN
Right=$BG_MARGIN
Top=$BG_MARGIN
Bottom=$BG_MARGIN

[InputPanel/ShadowMargin]
Left=$SHADOW_MARGIN
Right=$SHADOW_MARGIN
Top=$SHADOW_MARGIN
Bottom=$SHADOW_MARGIN

[InputPanel/Highlight]
$HIGHLIGHT_SECTION

[InputPanel/Highlight/Margin]
Left=$HL_MARGIN
Right=$HL_MARGIN
Top=$HL_MARGIN
Bottom=$HL_MARGIN

[InputPanel/PrevPage]
Image=prev.png

[InputPanel/PrevPage/ClickMargin]
Left=5
Right=5
Top=4
Bottom=4

[InputPanel/NextPage]
Image=next.png

[InputPanel/NextPage/ClickMargin]
Left=5
Right=5
Top=4
Bottom=4

[Menu]
NormalColor=$FOREGROUND
HighlightCandidateColor=$DARKER_BACKGROUND

[Menu/Background]
$BACKGROUND_SECTION

[Menu/Background/Margin]
Left=$BG_MARGIN
Right=$BG_MARGIN
Top=$BG_MARGIN
Bottom=$BG_MARGIN

[Menu/ContentMargin]
Left=$CONTENT_MARGIN
Right=$CONTENT_MARGIN
Top=$CONTENT_MARGIN_V
Bottom=$CONTENT_MARGIN_V

[Menu/CheckBox]
Image=radio.png

[Menu/SubMenu]
Image=arrow.png

[Menu/Highlight]
$HIGHLIGHT_SECTION

[Menu/Highlight/Margin]
Left=$HL_MARGIN
Right=$HL_MARGIN
Top=$HL_MARGIN
Bottom=$HL_MARGIN

[Menu/Separator]
Color=$MUTED

[Menu/TextMargin]
Left=5
Right=5
Top=5
Bottom=5
THEMEEOF

FONT="JetBrainsMono Nerd Font 9"
CLASSICUI_KEYS=(
  "Theme=omarchy"
  "DarkTheme=omarchy"
  "UseDarkTheme=False"
  # ClassicUI's "follow the system accent color" defaults to on and resolves
  # it from the desktop portal *asynchronously*, after the panel is already
  # up. That repaints the popup a while after startup with a color that has
  # nothing to do with the Omarchy theme generated here -- the popup coming
  # up unthemed and then changing on its own minutes later. The colors below
  # are already derived from the active theme, so pin it off.
  "UseAccentColor=False"
  "Font=$FONT"
  "MenuFont=$FONT"
)

# Apply through Fcitx5's own D-Bus config API rather than sed'ing
# classicui.conf behind its back. Fcitx5 owns that file while it runs: it
# rewrites it from its in-memory state on a periodic autosave and again on
# shutdown -- including the shutdown half of the restart below. An edit
# racing that save is silently reverted whenever it loses, which leaves the
# popup on Fcitx5's stock theme until something restarts it again. SetConfig
# puts the values in the live process, which then persists the file itself,
# so the restart that follows saves the right thing.
#
# This is inlined rather than shared with scripts/fcitx5_config.py because
# the hook is copied out of the plugin into
# ~/.config/omarchy/hooks/theme-set.d/ and has to stand on its own there.
# python-dbus is a guaranteed Omarchy dependency (pulled in transitively by
# uwsm, itself a hard dependency of the omarchy package).
# First arg is the snapshot path, the rest are the key=value pairs to apply.
apply_classicui_config() {
  python3 - "$CLASSICUI_SNAPSHOT" "$@" <<'PYEOF'
import os
import sys

try:
    import dbus
except ImportError:
    sys.exit(3)

URI = "fcitx://config/addon/classicui"


def unwrap(value):
    if isinstance(value, dbus.Dictionary):
        return {str(k): unwrap(v) for k, v in value.items()}
    if isinstance(value, dbus.Array):
        return [unwrap(v) for v in value]
    return str(value)


def build_asv(pyvalue):
    d = dbus.Dictionary(signature=dbus.Signature("sv"))
    for key, value in pyvalue.items():
        if isinstance(value, list):
            value = {str(i): item for i, item in enumerate(value)}
        if isinstance(value, dict):
            d[key] = dbus.Dictionary(build_asv(value), signature="sv", variant_level=1)
        else:
            d[key] = dbus.String(str(value), variant_level=1)
    return d


try:
    bus = dbus.SessionBus()
    obj = bus.get_object("org.fcitx.Fcitx5", "/controller")
    iface = dbus.Interface(obj, "org.fcitx.Fcitx.Controller1")
    # SetConfig is a full replace, not a merge: fetch everything, change only
    # the keys asked for, send the rest back untouched.
    value, _descriptor = iface.GetConfig(URI)
except dbus.exceptions.DBusException:
    sys.exit(3)

data = unwrap(value)
snapshot_path = sys.argv[1]
pairs = sys.argv[2:]

# Record what these keys looked like before this hook ever changed them, so a
# later uninstall can put them back. Written once and never overwritten: after
# the first apply the values on disk are ours, and re-taking the snapshot would
# capture those instead of the user's. GetConfig always reports an effective
# value (Fcitx5's default when nothing is set), so there is nothing ambiguous
# to record.
if not os.path.exists(snapshot_path):
    os.makedirs(os.path.dirname(snapshot_path), exist_ok=True)
    tmp = snapshot_path + ".tmp"
    with open(tmp, "w") as fh:
        for arg in pairs:
            key = arg.partition("=")[0]
            if key:
                fh.write(f"{key}={data.get(key, '')}\n")
    os.replace(tmp, snapshot_path)

for arg in pairs:
    key, sep, val = arg.partition("=")
    if sep:
        data[key] = val

iface.SetConfig(URI, dbus.Dictionary(build_asv(data), signature="sv", variant_level=1))
try:
    iface.ReloadAddonConfig("classicui")
except dbus.exceptions.DBusException:
    pass
PYEOF
}

mkdir -p "$(dirname "$FCITX_CLASSICUI_CONF")"
if ! apply_classicui_config "${CLASSICUI_KEYS[@]}"; then
  # Fcitx5 isn't running (or python-dbus is missing): writing the file is
  # safe precisely because nothing is up to overwrite it, and Fcitx5 reads
  # it on its next start.
  #
  # The snapshot has to be taken here too, and before the writes below --
  # otherwise the first apply on a machine where Fcitx5 was down would leave
  # no record, and the next successful run would snapshot our own values as if
  # they were the user's. A key the file doesn't set is recorded empty, which
  # scripts/uninstall.sh reads as "Fcitx5's default".
  if [[ ! -f "$CLASSICUI_SNAPSHOT" ]]; then
    mkdir -p "$(dirname "$CLASSICUI_SNAPSHOT")"
    : >"$CLASSICUI_SNAPSHOT.tmp"
    for key_value in "${CLASSICUI_KEYS[@]}"; do
      key="${key_value%%=*}"
      previous=""
      if [[ -f "$FCITX_CLASSICUI_CONF" ]] && grep -q "^$key=" "$FCITX_CLASSICUI_CONF"; then
        previous=$(sed -n "s|^$key=||p" "$FCITX_CLASSICUI_CONF" | head -1 | tr -d '\r')
      fi
      printf '%s=%s\n' "$key" "$previous" >>"$CLASSICUI_SNAPSHOT.tmp"
    done
    mv "$CLASSICUI_SNAPSHOT.tmp" "$CLASSICUI_SNAPSHOT"
  fi

  touch "$FCITX_CLASSICUI_CONF"
  for key_value in "${CLASSICUI_KEYS[@]}"; do
    key="${key_value%%=*}"
    if grep -q "^$key=" "$FCITX_CLASSICUI_CONF"; then
      sed -i "s|^$key=.*|$key_value|" "$FCITX_CLASSICUI_CONF"
    else
      printf '%s\n' "$key_value" >>"$FCITX_CLASSICUI_CONF"
    fi
  done
fi

if systemctl --user list-unit-files omarchy-fcitx5.service >/dev/null 2>&1; then
  systemctl --user restart omarchy-fcitx5.service
else
  fcitx5 -r --disable notificationitem >/dev/null 2>&1 &
  disown
fi
