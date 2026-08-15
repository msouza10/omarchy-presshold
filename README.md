# Press & Hold

A macOS-style press-and-hold accented character picker for [Omarchy](https://omarchy.org/).

Hold down a key like `a` and a popup lets you pick an alternate like `á`, `à`, `â`, `ã`... just like on macOS.

This plugin does **not** reimplement press-and-hold from scratch. Fcitx5's `keyboard-us` (and compatible) engine already has native long-press support — this plugin is a thin, portable layer that toggles it on/off from the bar and takes care of restarting Fcitx5 correctly.

## What it does

- Adds a small icon to the bar showing whether Press & Hold is on or off.
- Click it to open a toggle. Turning it on edits `~/.config/fcitx5/conf/keyboard.conf` idempotently — only the `EnableLongPress` and `Choose Modifier` keys, every other setting you already have is left untouched — and restarts Fcitx5 so the change actually takes effect.
- Turning it on also sets `Choose Modifier=None`, so pressing a plain number (`1`-`9`) selects a candidate. Fcitx5 defaults this to `Alt` (requiring `Alt+1`, `Alt+2`...); without overriding it, a bare number press isn't intercepted at all and gets typed into the field instead of picking a character.
- The icon always reflects the real state of `keyboard.conf`, even if you edit it by hand outside the plugin.

## Install

```bash
omarchy plugin add https://github.com/<your-username>/omarchy-presshold.git --enable
```

Local checkout:

```bash
omarchy plugin validate .
omarchy plugin add "$PWD" --enable
```

## Remove

```bash
omarchy plugin disable omaccerts.presshold
omarchy plugin remove omaccerts.presshold --yes
```

Removing the plugin does not revert `keyboard.conf` — turn the toggle off first if you want long-press disabled again.

## Requirements

- Omarchy Quattro shell.
- Fcitx5 with the `keyboard-us` (or another Fcitx5 Keyboard-engine-based) input method active. This is the default on a stock Omarchy install.
- `bash`, `sed`, `grep` (present on any Omarchy system).

## How it works

```text
Bar icon click
      ↓
scripts/toggle-longpress.sh enable|disable
      ↓
~/.config/fcitx5/conf/keyboard.conf  (EnableLongPress=True|False, Choose Modifier=None on enable, idempotent edit)
      ↓
systemctl --user restart omarchy-fcitx5.service   (real process restart, not just a reload)
      ↓
Fcitx5 Keyboard Engine's native long-press / candidate list
```

Fcitx5 stays fully responsible for input handling, key repeat, the candidate list, and committing text. This plugin only manages configuration and the bar UI.

## Known limitations (v0.1)

- Terminal emulators may behave differently — you may genuinely want `aaaa...` there instead of a popup. Fcitx5's own app-exclusion settings can be used for that; this plugin does not yet expose them.
- Only `EnableLongPress` and `Choose Modifier` are managed. `Choose Modifier` is applied on enable but not restored on disable — harmless either way, since there's no candidate list to select from once long-press is off. Candidate contents (which characters appear per key) and per-app blacklists are configured by Fcitx5 itself, not by this plugin, in this version.

## A note on restarting Fcitx5

On a stock Omarchy install, Fcitx5 runs under a systemd user service (`omarchy-fcitx5.service`, `Restart=always`). This plugin restarts Fcitx5 with `systemctl --user restart omarchy-fcitx5.service` — never a detached `fcitx5 -r &`. A detached replace process steals Fcitx5's D-Bus name out from under the service; the service's own process then fails to reacquire that name, exits, and systemd immediately restarts it, forever, in a silent fast crash-loop that leaves the orphan as the only working instance. `systemctl restart` stops the managed process first, so there's no name collision. If the unit isn't present, the script falls back to the detached replace.

## Extra: matching the candidate popup to your Omarchy theme

`extras/theme-set.d/fcitx5-theme.sh` is an optional, separate piece — not part of the plugin's own manifest/QML, and not installed automatically by `omarchy plugin add`. It regenerates a Fcitx5 ClassicUI theme ("omarchy") from your active Omarchy theme's colors (`omarchy-theme-color`): matching background/accent/foreground, rounded corners with a soft drop shadow (generated as 9-patch PNGs, since Fcitx5's theme format only takes flat colors or images — no `border-radius`), the system font (`JetBrainsMono Nerd Font`), and native compositor blur via Fcitx5's own `EnableBlur` (the KDE blur protocol, which Hyprland also implements — this does **not** touch Hyprland's own `decoration:blur:enabled`, so it works even on themes that keep window blur off).

To install it:

```bash
mkdir -p ~/.config/omarchy/hooks/theme-set.d
cp extras/theme-set.d/fcitx5-theme.sh ~/.config/omarchy/hooks/theme-set.d/
chmod +x ~/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh
~/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh   # apply immediately
```

Once installed, Omarchy re-runs it automatically on every `omarchy theme set` (via the `theme-set.d` hook contract), so the popup keeps matching whichever theme you switch to.

**Known limitation:** the popup's position relative to the text cursor (Fcitx5 anchors near the cursor rect it's given, extending right/down — not centered above the character like macOS) is not configurable; Fcitx5's `ClassicUI` doesn't expose an anchor/gravity setting for the panel itself, only for decorative overlays within the theme images.

## License

MIT
