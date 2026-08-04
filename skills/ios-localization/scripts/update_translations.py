#!/usr/bin/env python3
"""
Update Localizable.xcstrings with translations for a specific language.
Merges translations from a JSON file into the xcstrings file.

Usage: python update_translations.py <xcstrings_path> <lang_code> <translations.json>
Example: python update_translations.py ./Localizable.xcstrings fr translations_fr.json
"""

import json
import sys
from pathlib import Path

from xcstrings_patch import load_xcstrings, write_patched_entries


def update_translations(xcstrings_path: str, lang_code: str, translations: dict) -> int:
    """
    Update xcstrings file with translations for the given language.
    Returns the number of strings updated.
    """
    _, data = load_xcstrings(xcstrings_path)
    strings = data.get("strings", {})
    updated_keys: list[str] = []

    for key, translated_value in translations.items():
        if key not in strings:
            print(f"Warning: Key '{key}' not found in xcstrings", file=sys.stderr)
            continue

        if "localizations" not in strings[key]:
            strings[key]["localizations"] = {}

        strings[key]["localizations"][lang_code] = {
            "stringUnit": {
                "state": "translated",
                "value": translated_value,
            }
        }
        updated_keys.append(key)

    if updated_keys:
        write_patched_entries(xcstrings_path, data, updated_keys)

    return len(updated_keys)


def main():
    if len(sys.argv) != 4:
        print("Usage: python update_translations.py <xcstrings_path> <lang_code> <translations.json>", file=sys.stderr)
        print("Example: python update_translations.py ./Localizable.xcstrings fr translations_fr.json", file=sys.stderr)
        sys.exit(1)

    xcstrings_path = sys.argv[1]
    lang_code = sys.argv[2]
    translations_file = sys.argv[3]

    if not Path(xcstrings_path).exists():
        print(f"Error: File not found: {xcstrings_path}", file=sys.stderr)
        sys.exit(1)

    if translations_file == "-":
        translations = json.load(sys.stdin)
    else:
        with open(translations_file, "r", encoding="utf-8") as f:
            translations = json.load(f)

    count = update_translations(xcstrings_path, lang_code, translations)
    print(f"Updated {count} translations for '{lang_code}'")


if __name__ == "__main__":
    main()
