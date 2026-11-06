#!/usr/bin/env python3
"""ChillZone's rebranding of Olympus: one set of rules for the tree (once) and for upstream's patches.

  python3 scripts/rebrand.py tree     # every tracked file's text and path, in the working tree
  python3 scripts/rebrand.py patch    # stdin -> stdout: a patch of upstream's (git format-patch)

The rules: docs/superpowers/specs/2026-11-06-chillzone-fork-design.md, section 1.
"""
import os
import re
import subprocess
import sys

# Left as they are: the original's address, and the format and hash words ("olympus-record-1|",
# "olympus-strike-1:", "olympus-api-authorized:"...) that tests and saved data pin.
PROTECTED = re.compile(r"dnl-gentile/olympus-addon|olympus-(?=[a-z0-9])")
# The slash commands with no "olympus" in them, whole words only ("/oly" is not "/olympus").
SLASH = [
    (re.compile(r"/oly\b"), "/cz"),
    (re.compile(r"/ola\b"), "/cza"),
    (re.compile(r"/olc\b"), "/czc"),
    (re.compile(r"/oll\b"), "/czl"),
    (re.compile(r"/ol\b"), "/czn"),
    (re.compile(r"/ogarmy\b"), "/czarmy"),
]
# The words, the members' before the realm's.
WORDS = [
    ("OLYMPIAN", "CHILLZONER"), ("Olympian", "ChillZoner"), ("olympian", "chillzoner"),
    ("OLYMPUS", "CHILLZONE"), ("Olympus", "ChillZone"), ("olympus", "chillzone"),
]
WORD_RE = re.compile("|".join(re.escape(old) for old, _ in WORDS))
WORD_MAP = dict(WORDS)

SKIP = {"LICENSE", "UPSTREAM.md", "scripts/rebrand.py", "scripts/port-upstream.sh", "tests/rebrand_test.py"}
SKIP_DIRS = ("docs/superpowers/",)
BINARY = {".tga", ".png", ".jpg", ".jpeg", ".blp", ".ogg", ".mp3", ".wav", ".ttf", ".zip", ".pdf"}


def words(text):
    return WORD_RE.sub(lambda m: WORD_MAP[m.group(0)], text)


def rebrand(text):
    kept = []

    def keep(m):
        kept.append(m.group(0))
        return "\0%d\0" % (len(kept) - 1)

    text = PROTECTED.sub(keep, text)
    for pattern, new in SLASH:
        text = pattern.sub(new, text)
    text = words(text)
    return re.sub(r"\0(\d+)\0", lambda m: kept[int(m.group(1))], text)


def skipped(path):
    return path in SKIP or path.startswith(SKIP_DIRS)


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def tree():
    changed, moved, left = 0, 0, set()
    for path in tracked():
        if skipped(path):
            continue
        with open(path, "rb") as f:
            raw = f.read()
        if os.path.splitext(path)[1].lower() not in BINARY and b"\0" not in raw:
            text = raw.decode("utf-8", "surrogateescape")
            new = rebrand(text)
            if new != text:
                with open(path, "wb") as f:
                    f.write(new.encode("utf-8", "surrogateescape"))
                changed += 1
        target = words(path)
        if target != path:
            os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
            subprocess.run(["git", "mv", path, target], check=True)
            left.add(os.path.dirname(path))
            moved += 1
    for folder in sorted(left, key=len, reverse=True):
        while folder and os.path.isdir(folder) and not os.listdir(folder):
            os.rmdir(folder)
            folder = os.path.dirname(folder)
    print("rebrand: %d files rewritten, %d moved" % (changed, moved))


def patch():
    raw = sys.stdin.buffer.read()
    sys.stdout.buffer.write(rebrand(raw.decode("utf-8", "surrogateescape")).encode("utf-8", "surrogateescape"))


if __name__ == "__main__":
    if sys.argv[1:] == ["tree"]:
        tree()
    elif sys.argv[1:] == ["patch"]:
        patch()
    else:
        sys.exit(__doc__)
