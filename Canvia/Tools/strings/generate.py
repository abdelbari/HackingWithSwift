#!/usr/bin/env python3
"""Writes the app's translations from strings.json, the catalogue both
phones share (the Android twin's tools/strings/strings.json, the same
bytes). Run it after every change to the catalogue, and commit what it
writes:

  Canvia/Localizable.xcstrings   every entry but the Info.plist ones (and
                                 the Android twin's own plurals, below)
  Canvia/InfoPlist.xcstrings     the Info.plist usage descriptions
  Canvia.xcodeproj/project.pbxproj   the languages, in knownRegions
  strings.json                   itself, sorted, as both phones write it

The catalogue is keyed by the English the app shows. Each value holds the
seven translations: {"es": ..., "fr": ..., "de": ..., "pt-BR": ..., "it":
..., "ja": ..., "ar": ...}. Placeholders are %@ for text and %d for whole
numbers, in the English order, and every translation keeps them in that
order. Here a %d is written %lld, the key SwiftUI makes for an
interpolated Int, so Text("\\(n) pages") and tr("%d pages", n) find the
same entry.

A plural entry is keyed "<one>|<other>", "%d page|%d pages", and each
translation is an object of the CLDR forms its language needs. Here its
key is the English other form, %d written %lld:

  "%d page|%d pages"  ->  "%lld pages"

which is the key trn looks up (Tr.pluralKey), and each language's forms
are the entry's plural variations. Here the count is the first placeholder
of every form, so that whichever argument the system takes the plural
from, it is the count; trn passes it first. An entry whose count comes
later ("%@, %d hidden left out|...") is the Android twin's alone, whose
trn takes the count apart from the other values: it is checked like the
rest but not written here, where trn could not fill it.

Both catalogue files are written whole from strings.json: what Xcode adds
to them as it builds (the literals it finds that the catalogue has not)
goes, as it carries no translation. Every entry is "manual", so Xcode
never marks one stale that only tr and trn look up.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CATALOGUE = os.path.join(HERE, "strings.json")
LOCALIZABLE = os.path.join(ROOT, "Canvia", "Localizable.xcstrings")
INFOPLIST = os.path.join(ROOT, "Canvia", "InfoPlist.xcstrings")
PROJECT = os.path.join(ROOT, "Canvia.xcodeproj", "project.pbxproj")

LANGUAGES = ["es", "fr", "de", "pt-BR", "it", "ja", "ar"]
# The CLDR plural forms each language's translation of a plural entry has.
FORMS = {
    "ar": ["zero", "one", "two", "few", "many", "other"],
    "ja": ["other"],
}
DEFAULT_FORMS = ["one", "other"]


def forms_of(lang):
    return FORMS.get(lang, DEFAULT_FORMS)


def placeholders(text):
    """The %@ and %d in `text`, in order; a %% is a percent sign."""
    return [p for p in re.findall(r"%%|%@|%d", text) if p != "%%"]


def ios(text):
    """`text` as the iOS catalogue has it: each %d read as %lld."""
    return "%%".join(part.replace("%d", "%lld") for part in text.split("%%"))


def count_first(key):
    """Whether a plural entry's count is its first placeholder, as trn
    here fills it."""
    return placeholders(english_forms(key)["other"])[:1] == ["%d"]


def english_forms(key):
    one, _, other = key.partition("|")
    return {"one": one, "other": other}


def problems(catalogue):
    """What is wrong with the catalogue, as lines to print."""
    out = []
    for key, entry in catalogue.items():
        plural = "|" in key
        if not key.strip():
            out.append("an empty key")
            continue
        if plural:
            english = english_forms(key)
            if not english["one"].strip() or not english["other"].strip():
                out.append(f"{key!r}: a plural key is \"<one>|<other>\"")
                continue
            wanted = placeholders(english["other"])
            if placeholders(english["one"]) != wanted:
                out.append(f"{key!r}: its one and other forms have different placeholders")
            if "%d" not in wanted:
                out.append(f"{key!r}: a plural entry has no count, %d")
        else:
            wanted = placeholders(key)
        if not isinstance(entry, dict):
            out.append(f"{key!r}: not an object of translations")
            continue
        for lang in sorted(set(entry) - set(LANGUAGES)):
            out.append(f"{key!r}: {lang} is not one of the languages")
        for lang in LANGUAGES:
            value = entry.get(lang)
            if value is None:
                out.append(f"{key!r}: no {lang}")
                continue
            texts = []
            if plural:
                if not isinstance(value, dict) or sorted(value) != sorted(forms_of(lang)):
                    out.append(f"{key!r}: {lang} needs the forms {', '.join(forms_of(lang))}")
                    continue
                texts = list(value.values())
            elif isinstance(value, str):
                texts = [value]
            else:
                out.append(f"{key!r}: {lang} is not text")
                continue
            for text in texts:
                if not isinstance(text, str) or not text.strip():
                    out.append(f"{key!r}: {lang} is empty")
                elif placeholders(text) != wanted:
                    out.append(f"{key!r}: {lang} {text!r} does not keep {' '.join(wanted) or 'no placeholders'}")
    return out


def unit(value):
    return {"stringUnit": {"state": "translated", "value": ios(value)}}


def localizations(key, entry):
    if "|" in key:
        plural = {"en": english_forms(key)}
        plural.update({lang: entry[lang] for lang in LANGUAGES})
        return {lang: {"variations": {"plural": {form: unit(text) for form, text in forms.items()}}}
                for lang, forms in plural.items()}
    out = {"en": unit(key)}
    out.update({lang: unit(entry[lang]) for lang in LANGUAGES})
    return out


def write_json(path, value, separators=(",", " : ")):
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, separators=separators) + "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def usage_descriptions(project):
    """The Info.plist keys the build settings give text, and their English."""
    found = {}
    pattern = r'INFOPLIST_KEY_(NS\w+UsageDescription) = "((?:[^"\\]|\\.)*)";'
    for name, value in re.findall(pattern, project):
        value = re.sub(r"\\(.)", r"\1", value)
        if found.get(name, value) != value:
            sys.exit(f"{name} says different things in Debug and Release")
        found[name] = value
    return found


def with_regions(project):
    """The project with every language in knownRegions."""
    match = re.search(r"(knownRegions = \(\n)(.*?)(\n\t*\);)", project, re.S)
    if not match:
        sys.exit("project.pbxproj has no knownRegions")
    lines = match.group(2).split("\n")
    have = [line.strip().rstrip(",").strip('"') for line in lines]
    indent = re.match(r"\s*", lines[0]).group(0)
    for lang in LANGUAGES:
        if lang not in have:
            lines.append(indent + (f'"{lang}"' if "-" in lang else lang) + ",")
    return project[:match.start(2)] + "\n".join(lines) + project[match.end(2):]


def main():
    def pairs(items):
        keys = [k for k, _ in items]
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        if dupes:
            sys.exit(f"strings.json has {', '.join(map(repr, dupes))} twice")
        return dict(items)

    with open(CATALOGUE, encoding="utf-8") as f:
        catalogue = json.load(f, object_pairs_hook=pairs)
    found = problems(catalogue)
    if found:
        sys.exit("strings.json:\n  " + "\n  ".join(found))
    write_json(CATALOGUE, catalogue, separators=(",", ": "))

    with open(PROJECT, encoding="utf-8") as f:
        project = f.read()
    usage = usage_descriptions(project)
    plist_english = set(usage.values())

    strings = {}
    for key in sorted(catalogue):
        if key in plist_english or ("|" in key and not count_first(key)):
            continue
        name = ios(english_forms(key)["other"]) if "|" in key else ios(key)
        if name in strings:
            sys.exit(f"{key!r} has the key {name!r} here, which another entry has")
        strings[name] = {"extractionState": "manual", "localizations": localizations(key, catalogue[key])}
    write_json(LOCALIZABLE, {"sourceLanguage": "en", "strings": strings, "version": "1.0"})

    plist = {}
    for name, english in sorted(usage.items()):
        if english not in catalogue:
            print(f"note: {name} is not in strings.json, so it shows in English", file=sys.stderr)
            continue
        plist[name] = {"extractionState": "manual", "localizations": localizations(english, catalogue[english])}
    write_json(INFOPLIST, {"sourceLanguage": "en", "strings": plist, "version": "1.0"})

    updated = with_regions(project)
    if updated != project:
        with open(PROJECT, "w", encoding="utf-8") as f:
            f.write(updated)


if __name__ == "__main__":
    main()
