# Press & Hold

A macOS-style press-and-hold accented character picker for [Omarchy](https://omarchy.org/).

Hold down a key like `a` and a popup lets you pick an alternate like `á`, `à`, `â`, `ã`... just like on macOS.

This plugin does **not** reimplement press-and-hold from scratch. Fcitx5's `keyboard-us` (and compatible) engine already has native long-press support — this plugin is a thin, portable layer that toggles it on/off from the bar, lets you [reorder which accent each key offers first](#reordering-accents-the-keyboard-picker), and writes Fcitx5's config the way Fcitx5 itself expects.

## What it does

- Adds a small icon to the bar showing whether Press & Hold is on or off.
- Click it to open a toggle. Turning it on sets `EnableLongPress` and `Choose Modifier` through Fcitx5's own config API — only those two keys, every other setting you already have is left untouched — and takes effect immediately, with no restart.
- Turning it on also sets `Choose Modifier=None`, so pressing a plain number (`1`-`9`) selects a candidate. Fcitx5 defaults this to `Alt` (requiring `Alt+1`, `Alt+2`...); without overriding it, a bare number press isn't intercepted at all and gets typed into the field instead of picking a character.
- The first time you turn it on, it also installs the [theme-matching hook](#extra-matching-the-candidate-popup-to-your-omarchy-theme) (`extras/theme-set.d/fcitx5-theme.sh`) into `~/.config/omarchy/hooks/theme-set.d/`, so the popup matches your Omarchy theme out of the box — no manual step needed. It never overwrites a copy that's already there, so any edits you've made to it are left alone.
- **Customize accents ›** opens a [keyboard picker](#reordering-accents-the-keyboard-picker) for changing which accent a key offers first — `ã` ahead of `à` on `a`, say.
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
- `python3` with `python-dbus`, used to talk to Fcitx5's config API. Also present on any Omarchy system — it comes in transitively with `uwsm`, a hard dependency of the `omarchy` package. If it were missing, the on/off toggle falls back to editing `~/.config/fcitx5/conf/keyboard.conf` and restarting Fcitx5; the [keyboard picker](#reordering-accents-the-keyboard-picker) needs D-Bus and has no fallback.

## How it works

```text
Bar icon click
      ↓
scripts/toggle-longpress.sh enable|disable
      ↓
scripts/fcitx5_config.py → D-Bus SetConfig on fcitx://config/addon/keyboard
      ↓                     (EnableLongPress=True|False, Choose Modifier=None on enable)
the live Fcitx5 process applies it, then persists keyboard.conf itself
      ↓
Fcitx5 Keyboard Engine's native long-press / candidate list
```

Fcitx5 stays fully responsible for input handling, key repeat, the candidate list, and committing text. This plugin only manages configuration and the bar UI.

## Reordering accents: the keyboard picker

Fcitx5 ships a fixed candidate order per key: holding `a` offers `à` first, then `á`, `ã`, and so on. If you write Portuguese, having `ã` first saves a keystroke every single time. The popup's second view changes that order.

Click **Customize accents ›** in the bar popup and you get a drawing of a US keyboard:

- **Keys that have long-press candidates** are lit, and print the character they currently offer first underneath the legend. Click one to see its whole list.
- **Keys that don't** stay dim and inert. The board still draws the full keyboard — it just doesn't pretend every key is customizable.
- **⇧ Shift** swaps every legend for its shifted twin. Fcitx5 keeps uppercase (`A` → `À Á Â`) and shifted-symbol (`!` → `¡`, `$` → `¢ € £`) entries separately from their unshifted ones, so this puts each one under the key you would physically press for it.
- **Other scripts**, below the board, holds what no US key can reach: Fcitx5 also ships entries for Cyrillic, Hebrew and Arabic.

Picking a key lists its candidates in order with the current default marked; click any character to promote it to the front. The list is re-read from Fcitx5 afterwards rather than patched locally, so what you see is always the real order.

```text
Keyboard picker click
      ↓
scripts/reorder-candidates.py <key> <candidate>
      ↓
D-Bus SetConfig on fcitx://config/addon/keyboard/longpress
      ↓
the live Fcitx5 applies the new order, then persists keyboard-longpress.conf itself
```

The same commands are available from the installed plugin directory:

```bash
scripts/reorder-candidates.py --keys        # every long-press key and its candidates
scripts/reorder-candidates.py --status a    # one key's current order, one per line
scripts/reorder-candidates.py a ã           # promote ã to the front of a
```

Two things worth knowing about that config:

- **`SetConfig` on the longpress URI is a full replace, not a merge.** Sending back only the key you changed silently wipes every other key's candidates. So every write fetches the complete ~87-entry table, moves one character within one key, and sends the rest back untouched.
- **Reordering needs Fcitx5 running** (the script exits `3` otherwise). Unlike the on/off toggle, it has no edit-the-file-instead fallback: writing this table by hand would mean reimplementing Fcitx5's serialization for a ~87-entry nested structure, and if Fcitx5 is down there is no long-press to reorder in the first place. Start it and retry. See [the note on writing Fcitx5's config](#a-note-on-writing-fcitx5s-config) for why the toggle *does* have that fallback.

## Known limitations (v0.1)

- Terminal emulators may behave differently — you may genuinely want `aaaa...` there instead of a popup. Fcitx5's own app-exclusion settings can be used for that; this plugin does not yet expose them.
- Of the engine's own settings, only `EnableLongPress` and `Choose Modifier` are managed. `Choose Modifier` is applied on enable but not restored on disable — harmless either way, since there's no candidate list to select from once long-press is off.
- The keyboard picker reorders a key's candidates; it does not change *which* characters a key offers. Adding or removing candidates, and per-app blacklists (Fcitx5 ships with `konsole` excluded by default), are configured in Fcitx5 itself, not by this plugin, in this version.
- The picker draws a US layout. Keys that only exist on other physical layouts still reach their candidates through the **Other scripts** strip, but they aren't placed on the board.

## A note on writing Fcitx5's config

Config changes go through Fcitx5's own D-Bus API (`org.fcitx.Fcitx.Controller1.SetConfig`), not by editing `~/.config/fcitx5/conf/*.conf` behind its back.

Fcitx5 owns those files while it runs: it rewrites them from its **in-memory** state on a periodic autosave (roughly every 30 minutes) and again on shutdown — including the shutdown half of a `systemctl restart` issued to apply an edit. An edit written straight to the file therefore races Fcitx5's own save, and is silently reverted whenever it loses. That race is what made the toggle work only sometimes, and what could leave the candidate popup on Fcitx5's stock theme after a theme change. Going through `SetConfig` updates the live process, which then persists the file itself: no race, and no restart needed for a pure config change.

Writing the file directly is still the right move when Fcitx5 is **not** running — nothing is up to overwrite it, and Fcitx5 reads it on its next start — so that is exactly the fallback path the scripts take (and the only path that restarts anything).

## A note on restarting Fcitx5

The theme hook is the one place that still restarts Fcitx5, once, after regenerating the theme: the theme *name* never changes, only the PNGs behind it, and a running ClassicUI keeps the images it has already loaded. Nothing else restarts, so an enable that also installs the theme hook no longer restarts twice in a row — back-to-back restarts leave a window with no input method bound at all (Fcitx5's Wayland handshake takes ~10s) and can trip the unit's `StartLimitBurst`.

On a stock Omarchy install, Fcitx5 runs under a systemd user service (`omarchy-fcitx5.service`, `Restart=always`). This plugin restarts Fcitx5 with `systemctl --user restart omarchy-fcitx5.service` — never a detached `fcitx5 -r &`. A detached replace process steals Fcitx5's D-Bus name out from under the service; the service's own process then fails to reacquire that name, exits, and systemd immediately restarts it, forever, in a silent fast crash-loop that leaves the orphan as the only working instance. `systemctl restart` stops the managed process first, so there's no name collision. If the unit isn't present, the script falls back to the detached replace.

## Extra: matching the candidate popup to your Omarchy theme

`extras/theme-set.d/fcitx5-theme.sh` regenerates a Fcitx5 ClassicUI theme ("omarchy") from your active Omarchy theme's colors (`omarchy-theme-color`): matching background/accent/foreground, rounded corners with a soft drop shadow (generated as 9-patch PNGs, since Fcitx5's theme format only takes flat colors or images — no `border-radius`), the system font (`JetBrainsMono Nerd Font`), `UseAccentColor=False` (ClassicUI otherwise resolves a system accent color from the desktop portal *asynchronously*, repainting the popup a while after it is already up, with a color unrelated to your Omarchy theme), and native compositor blur via Fcitx5's own `EnableBlur` (the KDE blur protocol, which Hyprland also implements — this does **not** touch Hyprland's own `decoration:blur:enabled`, so it works even on themes that keep window blur off).

The plugin installs this automatically into `~/.config/omarchy/hooks/theme-set.d/` the first time you turn Press & Hold on — no manual step needed. To install or reapply it by hand instead:

```bash
mkdir -p ~/.config/omarchy/hooks/theme-set.d
cp extras/theme-set.d/fcitx5-theme.sh ~/.config/omarchy/hooks/theme-set.d/
chmod +x ~/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh
~/.config/omarchy/hooks/theme-set.d/fcitx5-theme.sh   # apply immediately
```

Once installed (by the plugin or by hand), Omarchy re-runs it automatically on every `omarchy theme set` (via the `theme-set.d` hook contract), so the popup keeps matching whichever theme you switch to.

**Optional dependency:** rounded corners and the drop shadow are generated with ImageMagick (`magick`), which is **not** part of a stock Omarchy install — only `omarchy-theme-color` is guaranteed present. If `magick` isn't found, the hook still applies colors, font, and blur, just with a flat rectangle (`Color`/`BorderColor`) instead of rounded corners. Install `imagemagick` if you want the rounded version.

**Known limitation:** the popup's position relative to the text cursor (Fcitx5 anchors near the cursor rect it's given, extending right/down — not centered above the character like macOS) is not configurable; Fcitx5's `ClassicUI` doesn't expose an anchor/gravity setting for the panel itself, only for decorative overlays within the theme images.

## License

MIT
