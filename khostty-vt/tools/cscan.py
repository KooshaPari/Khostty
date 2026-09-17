#!/usr/bin/env python3
"""Lexical scanning of C header text.

Declaration boundaries in C cannot be found with a line-oriented regex: a
`typedef struct { ... } Name;` body contains `;`, and a declarator may span
lines. This module provides the brace- and paren-aware scanning the binding
generator needs, plus the two source transformations that must happen before
any declaration is read: dropping comments, and blanking declarations that a
target guard excludes.

Split out of `gen_ffi.py` because scanning C text and emitting Rust are
separate concerns, and the combined file exceeded the repository's size
budget.
"""

from __future__ import annotations

import re

def strip_comments(src: str) -> str:
    """Remove /* */ and // comments without eating comment-like text in strings."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == '"' or ch == "'":
            quote = ch
            out.append(ch)
            i += 1
            while i < n:
                out.append(src[i])
                if src[i] == "\\":
                    i += 1
                    if i < n:
                        out.append(src[i])
                elif src[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if src.startswith("/*", i):
            end = src.find("*/", i + 2)
            # Preserve newlines so line-oriented parsing stays sane.
            block = src[i : end + 2] if end != -1 else src[i:]
            out.append("\n" * block.count("\n"))
            i = (end + 2) if end != -1 else n
            continue
        if src.startswith("//", i):
            end = src.find("\n", i)
            i = end if end != -1 else n
            continue
        out.append(ch)
        i += 1
    return "".join(out)


# Target guards the generator honours. libghostty-vt exposes a handful of
# declarations only on WebAssembly (`#ifdef __wasm__`); those symbols are not
# present in native builds, so binding them would advertise functions that
# cannot be linked. bindgen reaches the same conclusion via libclang.
# `#include <ghostty/vt/...>` lines, used to order headers the way the
# umbrella header does.
INCLUDE_RE = re.compile(r'#include\s+<(ghostty/vt/[^>]+)>')

TARGET_GUARDS = ("__wasm__",)


def strip_target_guards(src: str) -> tuple[str, list[str]]:
    """Blank out declarations inside `#ifdef __wasm__` style regions.

    Returns the modified source and the names found inside the guarded regions
    so the caller can report them as intentionally excluded.
    """
    out_lines: list[str] = []
    depth = 0
    excluded: list[str] = []
    for line in src.splitlines():
        stripped = line.strip()
        if depth == 0:
            guard = re.match(r"#\s*if(?:n?def|\s+defined\s*\(?\s*)?\s*(" + "|".join(re.escape(g) for g in TARGET_GUARDS) + r")\s*\)?\s*$", stripped)
            if guard:
                depth = 1
                continue
            out_lines.append(line)
            continue
        # inside a guarded region
        if re.match(r"#\s*if", stripped):
            depth += 1
        elif re.match(r"#\s*endif", stripped):
            depth -= 1
            if depth == 0:
                continue
        for fm in re.finditer(r"GHOSTTY_API\s+[^;{]*?\b(ghostty_[A-Za-z0-9_]+)\s*\(", line):
            excluded.append(fm.group(1))
        out_lines.append("")
    return "\n".join(out_lines), excluded


def strip_redundant_outer_parens(value: str) -> str:
    """Drop an outer paren pair that wraps the whole macro body.

    `#define FLAG (1 << 0)` becomes `1 << 0` so the emitted Rust does not trip
    `unused_parens`. Only a pair that encloses the entire body is removed.
    """
    while len(value) >= 2 and value[0] == "(" and value[-1] == ")":
        depth = 0
        encloses_all = True
        for index, ch in enumerate(value):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and index != len(value) - 1:
                    encloses_all = False
                    break
        if not encloses_all:
            break
        value = value[1:-1].strip()
    return value


def split_top_level(text: str, sep: str = ",") -> list[str]:
    """Split on `sep` at nesting depth zero."""
    parts, depth, current = [], 0, []
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if current:
        parts.append("".join(current))
    return parts


def find_matching(src: str, open_idx: int) -> int:
    """Index of the brace matching `src[open_idx]`."""
    depth = 0
    for i in range(open_idx, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError("unbalanced braces")


def find_decl_end(src: str, start: int) -> int:
    """Index of the `;` that terminates the declaration beginning at `start`.

    Scans brace- and paren-aware so that a struct body containing `;` does not
    truncate the declaration.
    """
    depth = 0
    i = start
    n = len(src)
    while i < n:
        ch = src[i]
        if ch in "{([":
            depth += 1
        elif ch in "})]":
            depth -= 1
        elif ch == ";" and depth == 0:
            return i
        i += 1
    raise ValueError("unterminated declaration")


