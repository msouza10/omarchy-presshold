#!/usr/bin/env python3
"""Reorder Fcitx5's press-and-hold candidate list for one key.

Fcitx5 exposes the long-press candidates (e.g. holding "a" offers
a a a a a a a) via D-Bus config at fcitx://config/addon/keyboard/longpress.
SetConfig on that URI is a FULL REPLACE, not a merge -- sending back just
the one changed key silently wipes every other key's candidates. So every
write here always fetches the complete ~87-entry structure, mutates only
the target key's Candidates order in memory, and sends the whole thing
back unchanged otherwise.

python-dbus is a guaranteed Omarchy dependency (pulled in transitively by
uwsm, itself a hard dependency of the omarchy package), so this does not
need the ImageMagick-style "might not be installed" fallback that
extras/theme-set.d/fcitx5-theme.sh needed.

The D-Bus plumbing lives in fcitx5_config.py, shared with
scripts/toggle-longpress.sh -- which uses the same API for the same reason:
config written straight into ~/.config/fcitx5/conf/*.conf loses a race with
Fcitx5's own autosave/shutdown save and gets silently reverted.

Usage:
  reorder-candidates.py <key> <candidate>   Promote <candidate> to the
                                             front of <key>'s list.
  reorder-candidates.py --status <key>      Print <key>'s current
                                             candidate order, one per line.
  reorder-candidates.py --keys              Print every long-press-enabled
                                             key and its candidates, one key
                                             per line: "<key> <c1> <c2> ...".
"""

import sys

from fcitx5_config import (
    Fcitx5Unavailable,
    controller,
    get_config,
    reload_addon,
    set_config,
)

URI = "fcitx://config/addon/keyboard/longpress"


def get_entries(iface):
    data = get_config(iface, URI)
    return data, data.get("Entries", {})


def find_entry(entries, key):
    for idx, entry in entries.items():
        if entry.get("Key") == key:
            return idx, entry
    return None, None


def ordered_candidates(entry):
    cands = entry.get("Candidates", {})
    return [cands[str(i)] for i in range(len(cands))]


def cmd_status(key):
    iface = controller()
    data, entries = get_entries(iface)
    idx, entry = find_entry(entries, key)
    if entry is None:
        print(f"error: no long-press entry for key '{key}'", file=sys.stderr)
        return 1
    for ch in ordered_candidates(entry):
        print(ch)
    return 0


def cmd_keys():
    iface = controller()
    _data, entries = get_entries(iface)
    rows = []
    for entry in entries.values():
        key = entry.get("Key")
        cands = ordered_candidates(entry)
        if not key or not cands:
            continue
        rows.append((key, cands))
    rows.sort(key=lambda row: row[0])
    for key, cands in rows:
        print(f"{key} {' '.join(cands)}")
    return 0


def cmd_promote(key, candidate):
    iface = controller()
    data, entries = get_entries(iface)
    idx, entry = find_entry(entries, key)
    if entry is None:
        print(f"error: no long-press entry for key '{key}'", file=sys.stderr)
        return 1

    chars = ordered_candidates(entry)
    if candidate not in chars:
        print(
            f"error: '{candidate}' is not a candidate for key '{key}' (have: {' '.join(chars)})",
            file=sys.stderr,
        )
        return 1

    if chars[0] == candidate:
        # Already first -- nothing to do, and nothing worth re-sending.
        return 0

    chars.remove(candidate)
    chars.insert(0, candidate)
    entry["Candidates"] = {str(i): ch for i, ch in enumerate(chars)}
    entries[idx] = entry
    data["Entries"] = entries

    set_config(iface, URI, data)
    reload_addon(iface, "keyboard")
    return 0


def main(argv):
    try:
        if len(argv) == 2 and argv[1] == "--keys":
            return cmd_keys()
        if len(argv) == 3 and argv[1] == "--status":
            return cmd_status(argv[2])
        if len(argv) == 3:
            return cmd_promote(argv[1], argv[2])
    except Fcitx5Unavailable as exc:
        # No edit-the-file fallback here, unlike toggle-longpress.sh: writing
        # this table by hand would mean reimplementing Fcitx5's serialization
        # for a ~87-entry nested structure, and with Fcitx5 down there is no
        # long-press to reorder in the first place. Say so and let the caller
        # start it.
        print(f"error: fcitx5 is not running: {exc}", file=sys.stderr)
        return 3
    print(__doc__, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
