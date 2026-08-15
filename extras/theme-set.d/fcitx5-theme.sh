#!/bin/bash
# Regenerates a Fcitx5 ClassicUI theme ("omarchy") from the currently active
# Omarchy theme's semantic colors (omarchy-theme-color), so the press-and-hold
# candidate popup matches the rest of the desktop instead of Fcitx5's stock
# default/default-dark theme. Runs on every `omarchy theme set` via the
# theme-set.d hook contract; also safe to run manually.
#
# Restarting via `systemctl --user restart omarchy-fcitx5.service` (not a
# detached `fcitx5 -r &`): Fcitx5 runs under that unit (Restart=always) on a
# stock Omarchy install. A detached replace process steals its D-Bus name,
# so the service's own process fails to reacquire it and gets endlessly
# restarted by systemd — a silent crash-loop.

set -euo pipefail

FCITX_THEME_DIR="$HOME/.local/share/fcitx5/themes/omarchy"
FCITX_CLASSICUI_CONF="$HOME/.config/fcitx5/conf/classicui.conf"
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

mkdir -p "$(dirname "$FCITX_CLASSICUI_CONF")"
touch "$FCITX_CLASSICUI_CONF"
for key_value in "Theme=omarchy" "DarkTheme=omarchy" "UseDarkTheme=False" "Font=JetBrainsMono Nerd Font 9" "MenuFont=JetBrainsMono Nerd Font 9"; do
  key="${key_value%%=*}"
  if grep -qF "$key=" "$FCITX_CLASSICUI_CONF"; then
    sed -i "s|^$key=.*|$key_value|" "$FCITX_CLASSICUI_CONF"
  else
    printf '%s\n' "$key_value" >>"$FCITX_CLASSICUI_CONF"
  fi
done

if systemctl --user list-unit-files omarchy-fcitx5.service >/dev/null 2>&1; then
  systemctl --user restart omarchy-fcitx5.service
else
  fcitx5 -r --disable notificationitem >/dev/null 2>&1 &
  disown
fi
