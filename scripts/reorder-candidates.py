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

Usage:
  reorder-candidates.py <key> <candidate>   Promote <candidate> to the
                                             front of <key>'s list.
  reorder-candidates.py --status <key>      Print <key>'s current
                                             candidate order, one per line.
"""

import sys

import dbus

URI = "fcitx://config/addon/keyboard/longpress"
BUS_NAME = "org.fcitx.Fcitx5"
OBJECT_PATH = "/controller"
IFACE = "org.fcitx.Fcitx.Controller1"


def controller():
    bus = dbus.SessionBus()
    obj = bus.get_object(BUS_NAME, OBJECT_PATH)
    return dbus.Interface(obj, IFACE)


def unwrap(value):
    """Recursively strip dbus wrapper types down to plain dict/list/str."""
    if isinstance(value, dbus.Dictionary):
        return {str(k): unwrap(v) for k, v in value.items()}
    if isinstance(value, dbus.Array):
        return [unwrap(v) for v in value]
    return str(value)


def build_asv(pyvalue):
    """Rebuild a plain dict (from unwrap()) into a dbus a{sv} structure.

    This dbus-python build has no dbus.Variant class -- variants are
    marked with variant_level=1 on the wrapped value instead (the classic
    python-dbus convention).
    """
    d = dbus.Dictionary(signature=dbus.Signature("sv"))
    for k, v in pyvalue.items():
        if isinstance(v, dict):
            d[k] = dbus.Dictionary(build_asv(v), signature="sv", variant_level=1)
        else:
            d[k] = dbus.String(str(v), variant_level=1)
    return d


def get_entries(iface):
    value, _descriptor = iface.GetConfig(URI)
    data = unwrap(value)
    return data, data.get("Entries", {})


def find_entry(entries, key):
    for idx, entry in entries.items():
        if entry.get("Key") == key:
            return idx, entry
    return None, None


def ordered_candidates(entry):
    cands = entry.get("Candidates", {})
    return [cands[str(i)] for i in range(len(cands))]


def apply_reload(iface):
    try:
        iface.ReloadAddonConfig("keyboard")
    except dbus.exceptions.DBusException as exc:
        print(f"warning: ReloadAddonConfig failed, config was still saved: {exc}", file=sys.stderr)


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

    payload = build_asv(data)
    iface.SetConfig(URI, dbus.Dictionary(payload, signature="sv", variant_level=1))
    apply_reload(iface)
    return 0


def main(argv):
    if len(argv) == 3 and argv[1] == "--status":
        return cmd_status(argv[2])
    if len(argv) == 3:
        return cmd_promote(argv[1], argv[2])
    print(__doc__, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
