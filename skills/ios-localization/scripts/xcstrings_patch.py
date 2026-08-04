#!/usr/bin/env python3
"""Helpers for patching Localizable.xcstrings without rewriting the whole file."""

from __future__ import annotations

import json
import re
from pathlib import Path


def load_xcstrings(path: str | Path) -> tuple[str, dict]:
    content = Path(path).read_text(encoding="utf-8")
    return content, json.loads(content)


def entry_key_prefix(key: str) -> str:
    return f"    {json.dumps(key, ensure_ascii=False)} : "


def find_json_object_span(text: str, start: int) -> tuple[int, int]:
    """Return [start, end) for a JSON object opening at `start` (the `{` index)."""
    depth = 0
    i = start
    in_string = False
    escape = False

    while i < len(text):
        char = text[i]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
        else:
            if char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return start, i + 1
        i += 1

    raise ValueError("Unbalanced braces while scanning xcstrings entry")


def find_entry_span(content: str, key: str) -> tuple[int, int] | None:
    prefix = entry_key_prefix(key)
    key_pos = content.find(prefix)
    if key_pos == -1:
        return None

    obj_start = content.find("{", key_pos + len(prefix))
    if obj_start == -1:
        raise ValueError(f"Malformed xcstrings entry for key: {key}")

    _, entry_end = find_json_object_span(content, obj_start)
    return key_pos, entry_end


def format_entry_block(key: str, entry: dict) -> str:
    """Serialize one strings entry using Xcode's ` : ` separator."""
    body = json.dumps(entry, ensure_ascii=False, indent=2)
    body = re.sub(r'": ', '" : ', body)
    lines = body.splitlines()
    first_line = f"{entry_key_prefix(key)}{lines[0]}"
    if len(lines) == 1:
        return first_line
    return first_line + "\n" + "\n".join(f"    {line}" for line in lines[1:])


def replace_entry(content: str, key: str, entry: dict) -> str:
    span = find_entry_span(content, key)
    if span is None:
        raise KeyError(key)

    start, end = span
    return content[:start] + format_entry_block(key, entry) + content[end:]


def write_patched_entries(path: str | Path, data: dict, keys: list[str]) -> None:
    """Rewrite only the given string entries, preserving the rest of the file."""
    content, _ = load_xcstrings(path)
    strings = data.get("strings", {})

    for key in keys:
        if key not in strings:
            raise KeyError(key)
        content = replace_entry(content, key, strings[key])

    Path(path).write_text(content, encoding="utf-8")
