#!/usr/bin/env python3
"""
Mark strings as shouldTranslate: false in Localizable.xcstrings.
Removes existing localizations for marked strings.

Usage: python mark_non_translatable.py <xcstrings_path> <key1> [key2] [key3] ...
Example: python mark_non_translatable.py ./Localizable.xcstrings "1:2" "16:9" "A4" "OK"
"""

import sys
from pathlib import Path

from xcstrings_patch import load_xcstrings, write_patched_entries


def mark_non_translatable(xcstrings_path: str, keys: list) -> int:
    """
    Mark specified keys as shouldTranslate: false.
    Returns the number of keys updated.
    """
    _, data = load_xcstrings(xcstrings_path)
    strings = data.get("strings", {})
    updated_keys: list[str] = []

    for key in keys:
        if key in strings:
            if "localizations" in strings[key]:
                del strings[key]["localizations"]
            strings[key]["shouldTranslate"] = False
            updated_keys.append(key)
            print(f"Marked: {key}")
        else:
            print(f"Warning: Key not found: {key}", file=sys.stderr)

    if updated_keys:
        write_patched_entries(xcstrings_path, data, updated_keys)

    return len(updated_keys)


def main():
    if len(sys.argv) < 3:
        print("Usage: python mark_non_translatable.py <xcstrings_path> <key1> [key2] ...", file=sys.stderr)
        print('Example: python mark_non_translatable.py ./Localizable.xcstrings "1:2" "16:9"', file=sys.stderr)
        sys.exit(1)

    xcstrings_path = sys.argv[1]
    keys = sys.argv[2:]

    if not Path(xcstrings_path).exists():
        print(f"Error: File not found: {xcstrings_path}", file=sys.stderr)
        sys.exit(1)

    count = mark_non_translatable(xcstrings_path, keys)
    print(f"\nTotal: {count} strings marked as shouldTranslate: false")


if __name__ == "__main__":
    main()
