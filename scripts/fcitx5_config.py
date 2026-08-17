#!/usr/bin/env python3
"""Read and write Fcitx5 addon config through Fcitx5's own D-Bus API.

Why not just sed ~/.config/fcitx5/conf/*.conf: Fcitx5 owns those files while
it runs. It rewrites them from its in-memory state on a periodic autosave
(~every 30 minutes) and again on shutdown -- including the shutdown half of
the `systemctl restart` that used to be how these scripts applied an edit.
So a sed done behind its back races with Fcitx5's own save and gets silently
reverted whenever it loses, which is exactly the "the toggle worked, then it
didn't, then the theme came back on its own" behaviour. Going through
SetConfig updates the live process and lets *it* persist the file, so there
is no race and, for pure config changes, no restart at all.

SetConfig is a FULL REPLACE, not a merge: sending back only the changed key
silently wipes every other key in that addon's config. Every write here
fetches the complete config, mutates only the requested keys, and sends the
rest back untouched.

python-dbus is a guaranteed Omarchy dependency (pulled in transitively by
uwsm, itself a hard dependency of the omarchy package).

Usable as a module (reorder-candidates.py imports it) or as a CLI:

  fcitx5_config.py get <addon> <key>             print one top-level key
  fcitx5_config.py set <addon> <key>=<value>...  set top-level keys

Exit codes: 0 ok, 2 usage or unknown key, 3 Fcitx5 not reachable on the
session bus. Callers treat 3 as "fall back to editing the file directly" --
safe precisely because nothing is running to overwrite it, and Fcitx5 reads
the file on its next start.
"""

import sys

try:
    import dbus
except ImportError as exc:  # pragma: no cover - only on a broken install
    print(f"error: python-dbus is required: {exc}", file=sys.stderr)
    sys.exit(3)

BUS_NAME = "org.fcitx.Fcitx5"
OBJECT_PATH = "/controller"
IFACE = "org.fcitx.Fcitx.Controller1"

EXIT_USAGE = 2
EXIT_UNAVAILABLE = 3


class Fcitx5Unavailable(Exception):
    """Fcitx5 is not running, or not answering on the session bus."""


def addon_uri(addon: str) -> str:
    return f"fcitx://config/addon/{addon}"


def controller():
    try:
        bus = dbus.SessionBus()
        obj = bus.get_object(BUS_NAME, OBJECT_PATH)
    except dbus.exceptions.DBusException as exc:
        raise Fcitx5Unavailable(str(exc)) from exc
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

    This dbus-python build has no dbus.Variant class -- variants are marked
    with variant_level=1 on the wrapped value instead (the classic
    python-dbus convention). Fcitx5 models lists as dicts keyed by the
    stringified index, so a list that survived unwrap() is converted back
    into that shape rather than sent as an array.
    """
    d = dbus.Dictionary(signature=dbus.Signature("sv"))
    for key, value in pyvalue.items():
        if isinstance(value, list):
            value = {str(i): item for i, item in enumerate(value)}
        if isinstance(value, dict):
            d[key] = dbus.Dictionary(build_asv(value), signature="sv", variant_level=1)
        else:
            d[key] = dbus.String(str(value), variant_level=1)
    return d


def get_config(iface, uri):
    try:
        value, _descriptor = iface.GetConfig(uri)
    except dbus.exceptions.DBusException as exc:
        raise Fcitx5Unavailable(str(exc)) from exc
    return unwrap(value)


def set_config(iface, uri, data):
    payload = build_asv(data)
    iface.SetConfig(uri, dbus.Dictionary(payload, signature="sv", variant_level=1))


def reload_addon(iface, addon):
    try:
        iface.ReloadAddonConfig(addon)
    except dbus.exceptions.DBusException as exc:
        print(
            f"warning: ReloadAddonConfig({addon}) failed, config was still saved: {exc}",
            file=sys.stderr,
        )


def get_addon_value(addon, key):
    """Return one top-level key of <addon>'s live config."""
    iface = controller()
    data = get_config(iface, addon_uri(addon))
    return data[key]


def set_addon_values(addon, values):
    """Merge `values` into <addon>'s config and reload it.

    Returns True if anything actually changed.
    """
    iface = controller()
    uri = addon_uri(addon)
    data = get_config(iface, uri)

    changed = False
    for key, value in values.items():
        if data.get(key) != value:
            data[key] = value
            changed = True

    if changed:
        set_config(iface, uri, data)
        reload_addon(iface, addon)
    return changed


def cmd_get(addon, key):
    try:
        print(get_addon_value(addon, key))
    except KeyError:
        print(f"error: addon '{addon}' has no key '{key}'", file=sys.stderr)
        return EXIT_USAGE
    return 0


def cmd_set(addon, pairs):
    values = {}
    for pair in pairs:
        key, sep, value = pair.partition("=")
        if not sep or not key:
            print(f"error: expected <key>=<value>, got '{pair}'", file=sys.stderr)
            return EXIT_USAGE
        values[key] = value
    set_addon_values(addon, values)
    return 0


def main(argv):
    try:
        if len(argv) == 4 and argv[1] == "get":
            return cmd_get(argv[2], argv[3])
        if len(argv) >= 4 and argv[1] == "set":
            return cmd_set(argv[2], argv[3:])
    except Fcitx5Unavailable as exc:
        print(f"fcitx5 unavailable: {exc}", file=sys.stderr)
        return EXIT_UNAVAILABLE
    print(__doc__, file=sys.stderr)
    return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main(sys.argv))
