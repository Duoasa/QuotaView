#!/usr/bin/env python3
"""Audit app-owned bilingual Swift literals against the ja/ko/es catalog.

Run from any directory. Traditional Chinese derives from the Chinese template;
Swift smoke tests verify script conversion never touches interpolated user data.
This scans regular strings and balanced interpolation, not arbitrary Swift syntax.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/QuotaView/Resources/AppTranslations.json"
LANGUAGES = ("ja", "ko", "es")


def string(source, start):
    assert source[start] == '"'
    index, value, arguments = start + 1, "", 0
    while index < len(source):
        character = source[index]
        if character == '"':
            return value, index + 1
        if character == "\\":
            escaped = source[index + 1]
            if escaped == "(":
                cursor, depth = index + 2, 1
                while depth:
                    if source[cursor] == '"':
                        _, cursor = string(source, cursor)
                        continue
                    depth += (source[cursor] == "(") - (source[cursor] == ")")
                    cursor += 1
                value += "{{" + str(arguments) + "}}"
                arguments += 1
                index = cursor
                continue
            value += {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\", "0": "\0"}.get(escaped, escaped)
            index += 2
            continue
        value += character
        index += 1
    raise ValueError("Unterminated Swift string")


def templates():
    paths = sorted((ROOT / "Sources/QuotaView").glob("*.swift"))
    paths.append(ROOT / "Sources/QuotaViewWidget/QuotaViewWidget.swift")
    # text(), bilingual IslandDetailText initializers, and fixed effect-name tuples.
    pattern = r'\b(?:text|init)\s*\(\s*|\(\s*(?="[\u4e00-\u9fff])'
    for path in paths:
        source = path.read_text()
        for match in re.finditer(pattern, source):
            index = match.end()
            if source[index:index + 1] != '"':
                continue
            chinese, index = string(source, index)
            comma = re.match(r"\s*,\s*", source[index:])
            if not comma:
                continue
            index += comma.end()
            if source[index:index + 1] != '"':
                continue
            english, index = string(source, index)
            if not re.match(r"\s*[,)]", source[index:]) or not re.search(r"[\u4e00-\u9fff]", chinese):
                continue
            yield english, f"{path.relative_to(ROOT)}:{source.count(chr(10), 0, match.start()) + 1}"


def main():
    catalog = json.loads(CATALOG.read_text())
    errors = []
    checked = set()
    for key, location in templates():
        checked.add(key)
        if key not in catalog:
            errors.append(f"{location}: missing template {key!r}")
    for key, entries in catalog.items():
        placeholders = sorted(re.findall(r"\{\{\d+\}\}", key))
        for language in LANGUAGES:
            value = entries.get(language)
            if not value:
                errors.append(f"{language}: empty translation for {key!r}")
            elif sorted(re.findall(r"\{\{\d+\}\}", value)) != placeholders:
                errors.append(f"{language}: placeholder mismatch for {key!r}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"PASS: {len(checked)} source templates covered; {len(catalog)} catalog entries × {len(LANGUAGES)} translations; placeholders match.")


if __name__ == "__main__":
    main()
