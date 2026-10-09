#!/usr/bin/env python3
"""Fail when the vendored sandbox API's ECALL numbers disagree with the addon's.

The addon's numbers are read from godot-sandbox's program/cpp/docker/api/syscalls.h
(src/syscalls.h links to it) at the commit vendor/sandbox-api/CITATION.cff names,
or from --addon FILE.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDORED = ROOT / "vendor/sandbox-api/docker/api/syscalls.h"
CITATION = ROOT / "vendor/sandbox-api/CITATION.cff"
SANDBOX_REPO = ROOT.parent.parent / "4-entities/godot-sandbox"
HEADER = "program/cpp/docker/api/syscalls.h"

DEFINE = re.compile(r"^\s*#\s*define\s+(GAME_API_BASE|ECALL_\w+)\s+(.+?)\s*(?://.*)?$", re.M)
VALUE = re.compile(r"^\(?\s*(?:(GAME_API_BASE)\s*\+\s*)?(\d+)\s*\)?$")


def ecalls(text):
    base = None
    out = {}
    for name, expr in DEFINE.findall(text):
        m = VALUE.match(expr)
        if not m:
            continue
        if m.group(1) and base is None:
            continue
        value = int(m.group(2)) + (base if m.group(1) else 0)
        if name == "GAME_API_BASE":
            base = value
        else:
            out[name] = value
    return out


def compare(vendored, addon):
    v, a = ecalls(vendored), ecalls(addon)
    problems = []
    for side, table in (("vendored", v), ("addon", a)):
        if "ECALL_LAST" not in table:
            problems.append(f"{side} header defines no ECALL_LAST")
    if "ECALL_LAST" in v and "ECALL_LAST" in a and v["ECALL_LAST"] != a["ECALL_LAST"]:
        problems.append(f"ECALL_LAST: vendored {v['ECALL_LAST']}, addon {a['ECALL_LAST']}")
    for name in sorted(set(v) | set(a)):
        if name == "ECALL_LAST":
            continue
        if name not in a:
            problems.append(f"{name} is vendored but not in the addon")
        elif name not in v:
            problems.append(f"{name} is in the addon but not vendored")
        elif v[name] != a[name]:
            problems.append(f"{name}: vendored {v[name]}, addon {a[name]}")
    return problems, v, a


def cited_commit(text):
    m = re.search(r"^commit:\s*([0-9a-f]{7,40})\s*$", text, re.M)
    return m.group(1) if m else None


def addon_header(repo, ref):
    r = subprocess.run(["git", "-C", str(repo), "show", f"{ref}:{HEADER}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"cannot read {HEADER} at {ref} in {repo}: {r.stderr.strip()}")
    return r.stdout


def self_test():
    good = "#define GAME_API_BASE 500\n#define ECALL_PRINT (GAME_API_BASE + 0)\n" \
           "#define ECALL_ARRAY_WINDOW (GAME_API_BASE + 67)\n#define ECALL_LAST (GAME_API_BASE + 70)\n"
    cases = [
        ("identical headers pass", good, good, True),
        ("ECALL_LAST one short is rejected", good.replace("+ 70", "+ 67"), good, False),
        ("ECALL_LAST missing from the vendored side is rejected",
         good.replace("#define ECALL_LAST (GAME_API_BASE + 70)\n", ""), good, False),
        ("ECALL_LAST missing from the addon side is rejected",
         good, good.replace("#define ECALL_LAST (GAME_API_BASE + 70)\n", ""), False),
        ("a renumbered ECALL is rejected", good.replace("+ 67", "+ 66"), good, False),
        ("an ECALL only the addon has is rejected",
         good, good + "#define ECALL_PACKED_ACQUIRE (GAME_API_BASE + 68)\n", False),
        ("a different GAME_API_BASE is rejected", good.replace("500", "400"), good, False),
        ("a trailing comment is ignored", good.replace("+ 0)", "+ 0) // print"), good, True),
    ]
    failed = 0
    for name, v, a, want in cases:
        got = not compare(v, a)[0]
        ok = got == want
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name}")
    if cited_commit("commit: 5f19275e1c6f9e15c7564e564ecd22d829a4fc13\n") is None \
            or cited_commit("repository-code: x\n") is not None:
        print("FAIL citation commit parsing")
        failed += 1
    else:
        print("ok   citation commit parsing (present and absent)")
    try:
        addon_header(ROOT, "0" * 40)
        print("FAIL an unreadable addon ref is not an error")
        failed += 1
    except RuntimeError:
        print("ok   an unreadable addon ref is an error")
    print(f"{len(cases) + 2 - failed}/{len(cases) + 2} controls held")
    return 1 if failed else 0


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--addon", type=Path, help="the addon's syscalls.h, instead of reading git")
    p.add_argument("--sandbox-repo", type=Path, default=SANDBOX_REPO)
    p.add_argument("--ref", help="godot-sandbox ref (default: the CITATION.cff commit)")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    try:
        if args.addon:
            addon, source = args.addon.read_text(), str(args.addon)
        else:
            ref = args.ref or cited_commit(CITATION.read_text())
            if ref is None:
                raise RuntimeError(f"{CITATION} names no commit")
            addon, source = addon_header(args.sandbox_repo, ref), f"{args.sandbox_repo}@{ref}"
        vendored = VENDORED.read_text()
    except (OSError, RuntimeError) as e:
        print(f"FAIL {e}")
        return 1
    problems, v, a = compare(vendored, addon)
    for line in problems:
        print(f"FAIL {line}")
    if problems:
        print(f"{len(problems)} disagreement(s) against {source}")
        return 1
    print(f"ok   {len(v)} ECALL defines agree with {source}; ECALL_LAST = {v['ECALL_LAST']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
