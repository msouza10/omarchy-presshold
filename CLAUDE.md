# Project notes

## Claude Code session

The plugin was built in this Claude Code session:

```
651ce3ec-e375-43b5-bc5c-e7ee79f8639c
```

## Branches

- `master` — the shipped plugin: bar toggle, `scripts/toggle-longpress.sh`, and the optional theme hook in `extras/`.
- `visual/accent-reorder-ui` — visual-only mockup of the accent-reordering UI (key grid + tap-to-promote candidate chips). Runs on hardcoded sample data; nothing wired to Fcitx5.
- `backend/accent-reorder` — `scripts/reorder-candidates.py`, which actually reorders a key's long-press candidates via Fcitx5's D-Bus config. Not wired to any UI.

The two feature branches were developed in parallel and are meant to be joined once the UI design is settled.

## Gotchas worth remembering

- **Restart Fcitx5 only via `systemctl --user restart omarchy-fcitx5.service`.** A detached `fcitx5 -r &` steals the service's D-Bus name and puts systemd into a silent crash-loop.
- **`SetConfig` on the Fcitx5 long-press config is a full replace, not a merge.** Always read all ~87 entries, change one, send them all back.
- **`Column.implicitWidth` is read-only** — assigning it is a hard QML error that stops the plugin loading. Wrap the Column in a plain `Item` and set `implicitWidth` there.
- **`PopupCard` has `verticalContentInset` but no horizontal counterpart.** `contentWidth` must add `padding * 2 + Border.left + Border.right` by hand, or content flush to the right edge gets clipped.
- **ImageMagick is not an Omarchy dependency**; `python-dbus` is (transitively, via `uwsm`).
