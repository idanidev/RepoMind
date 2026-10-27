#!/usr/bin/env python3
"""Localization checks that need no compiler, so they run in seconds on Linux.

1. en and es have the same keys, no key twice, and the same printf specifiers in each pair
   (app, App Shortcuts, Info.plist and the widget).
2. Every key of Localizable.stringsdict (the plurals) is well formed, has its fallback in
   Localizable.strings, exists in both languages, and is looked up with string interpolation
   (`String(localized: "key \\(n)")`): a lookup of the bare key skips the plural rule.
3. Every literal key a Swift file hands to Text, Label, Button, String(localized:)... exists
   in the strings of the target that file belongs to.

usage: strings.py          (from anywhere; the repo root is found from this file)
"""
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:l{0,2}|h{0,2}|z|t|j)[@dDuUxXoOfeEgGcCsSpaAF]")
PAIR = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
KEY = re.compile(r"[a-z][a-z0-9_]*(?: %[@dlldx]+)*")

problems: list[str] = []


def fail(message: str) -> None:
    problems.append(message)
    print(f"::error::{message}")


def parse(path: Path) -> tuple[dict[str, str], list[str]]:
    pairs = PAIR.findall(path.read_text(encoding="utf-8"))
    return dict(pairs), [key for key, _ in pairs]


def specifiers(text: str) -> list[str]:
    return SPEC.findall(text.replace("%%", ""))


# 1. parity ------------------------------------------------------------------------------------

widget = sorted((ROOT / "RepoMindWidget").glob("*.lproj/Localizable.strings"))
pairs = [
    (ROOT / "RepoMind/en.lproj/Localizable.strings", ROOT / "RepoMind/es.lproj/Localizable.strings"),
    (ROOT / "RepoMind/en.lproj/AppShortcuts.strings", ROOT / "RepoMind/es.lproj/AppShortcuts.strings"),
    (ROOT / "RepoMind/en.lproj/InfoPlist.strings", ROOT / "RepoMind/es.lproj/InfoPlist.strings"),
]
if len(widget) == 2:
    pairs.append((widget[0], widget[1]))

app_keys: set[str] = set()
widget_keys: set[str] = set()
for en_path, es_path in pairs:
    english, english_keys = parse(en_path)
    spanish, spanish_keys = parse(es_path)
    for path, keys in ((en_path, english_keys), (es_path, spanish_keys)):
        for key in sorted({k for k in keys if keys.count(k) > 1}):
            fail(f"{path.relative_to(ROOT)}: the key {key!r} appears more than once")
    for key in sorted(set(english) ^ set(spanish)):
        where = "only in en" if key in english else "only in es"
        fail(f"{en_path.parent.name}/{en_path.name}: {key!r} is {where}")
    for key in sorted(set(english) & set(spanish)):
        if specifiers(english[key]) != specifiers(spanish[key]):
            fail(
                f"{en_path.name}: {key!r} takes {specifiers(english[key])} in en"
                f" but {specifiers(spanish[key])} in es")
    if en_path.parent.parent.name == "RepoMindWidget":
        widget_keys |= set(english)
    elif en_path.name == "Localizable.strings":
        app_keys |= set(english)
print(f"strings: {len(app_keys)} app keys and {len(widget_keys)} widget keys, en and es in step")

# 2. plurals -----------------------------------------------------------------------------------

plural_keys: dict[str, set[str]] = {}
for lang in ("en", "es"):
    path = ROOT / f"RepoMind/{lang}.lproj/Localizable.stringsdict"
    if not path.exists():
        continue
    try:
        entries = plistlib.loads(path.read_bytes())
    except Exception as error:  # a plist that does not parse is dropped by the system, silently
        fail(f"{path.relative_to(ROOT)} is not a valid property list: {error}")
        continue
    fallback, _ = parse(ROOT / f"RepoMind/{lang}.lproj/Localizable.strings")
    plural_keys[lang] = set(entries)
    for key, entry in entries.items():
        if key not in fallback:
            fail(f"{lang}.lproj/Localizable.stringsdict: {key!r} has no fallback in Localizable.strings")
        variable = re.fullmatch(r"%#@(\w+)@", entry.get("NSStringLocalizedFormatKey", ""))
        rule = entry.get(variable.group(1)) if variable else None
        if (
            not isinstance(rule, dict)
            or rule.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType"
            or rule.get("NSStringFormatValueTypeKey") != "lld"
            or "other" not in rule
        ):
            fail(f"{lang}.lproj/Localizable.stringsdict: {key!r} is not a well formed plural rule")
            continue
        if key in fallback and specifiers(rule["other"]) != specifiers(fallback[key]):
            fail(f"{lang}.lproj/Localizable.stringsdict: {key!r} takes other numbers than its fallback")
        if len(specifiers(rule["other"])) != 1 or len(specifiers(rule.get("one", ""))) > 1:
            fail(f"{lang}.lproj/Localizable.stringsdict: {key!r} should take exactly one number")
if len(plural_keys) == 2 and plural_keys["en"] != plural_keys["es"]:
    fail(f"the plural keys differ between en and es: {sorted(plural_keys['en'] ^ plural_keys['es'])}")

swift_files = [
    ROOT / name
    for name in subprocess.run(
        ["git", "ls-files", "*.swift"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.split()
]
sources = {path: path.read_text(encoding="utf-8") for path in swift_files}
for key in sorted(next(iter(plural_keys.values()), set())):
    for path, source in sources.items():
        if f'"{key}"' in source:
            fail(f"{path.relative_to(ROOT)}: {key!r} is a plural; look it up with interpolation, not by name")
print(f"plurals: {len(next(iter(plural_keys.values()), set()))} keys")

# 3. keys that exist ---------------------------------------------------------------------------

CALL = re.compile(
    r'String\(localized:\s*"([^"\\]+)"'
    r'|(?:Text|Label|Button|Section|Toggle|Link|TextField|Picker|navigationTitle)\(\s*"([^"\\]+)"')
checked = 0
for path, source in sources.items():
    known = widget_keys if "RepoMindWidget" in path.parts else app_keys
    if path.parts[-2] == "RepoMindTests" or "RepoMindUITests" in path.parts:
        continue
    for literal in (a or b for a, b in CALL.findall(source)):
        if not KEY.fullmatch(literal):
            continue  # prose, a format, a symbol name: not one of our snake_case keys
        checked += 1
        if literal not in known:
            fail(f"{path.relative_to(ROOT)}: the key {literal!r} is not in {'the widget' if known is widget_keys else 'the app'} strings")
print(f"keys: {checked} literal keys looked up in Swift")

sys.exit(1 if problems else 0)
