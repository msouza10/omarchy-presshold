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
fcitx5 -r --disable notificationitem   (real process restart, not just a reload)
      ↓
Fcitx5 Keyboard Engine's native long-press / candidate list
```

Fcitx5 stays fully responsible for input handling, key repeat, the candidate list, and committing text. This plugin only manages configuration and the bar UI.

## Known limitations (v0.1)

- Terminal emulators may behave differently — you may genuinely want `aaaa...` there instead of a popup. Fcitx5's own app-exclusion settings can be used for that; this plugin does not yet expose them.
- Only `EnableLongPress` and `Choose Modifier` are managed. `Choose Modifier` is applied on enable but not restored on disable — harmless either way, since there's no candidate list to select from once long-press is off. Candidate contents (which characters appear per key) and per-app blacklists are configured by Fcitx5 itself, not by this plugin, in this version.

## License

MIT
