#!/usr/bin/env python3
"""Generate `src/ffi.rs` from the libghostty-vt C headers.

The upstream C API is declared with a small set of conventions:

* `GHOSTTY_API <ret> <name>(<params>);` for exported functions
* `typedef enum GHOSTTY_ENUM_TYPED { ... } Name;` where every enum is backed
  by `int` (the Zig implementation uses `c_int`), so each becomes a
  `c_int` type alias plus `pub const` values to avoid depending on Rust enum
  layout or exhaustiveness rules.
* `typedef struct { ... } Name;` for value structs, `typedef union { ... }`
  for tagged-union payloads, and `typedef struct XImpl* X;` for opaque handles.
* Anonymous-backing types such as `GhosttyMods` (`uint16_t`) and `GhosttyCell`
  (`uint64_t`) as plain aliases.

Rather than hand-transcribe ~170 functions, this script parses the headers with
a small recursive-descent reader and emits mechanically faithful `extern "C"`
declarations. Anything it cannot represent is reported in the generated file's
`SKIPPED` section instead of being silently dropped, and the drift test
(`tests/ffi_coverage.rs`) re-parses the headers to prove nothing was lost.

Usage:
    python3 tools/gen_ffi.py            # rewrite src/ffi.rs
    python3 tools/gen_ffi.py --check    # exit 1 if src/ffi.rs is stale
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
CRATE_ROOT = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(CRATE_ROOT)
INCLUDE_DIR = os.path.join(REPO_ROOT, "include")
UMBRELLA = os.path.join(INCLUDE_DIR, "ghostty", "vt.h")
OUT_PATH = os.path.join(CRATE_ROOT, "src", "ffi.rs")

# ---------------------------------------------------------------------------
# C type mapping
# ---------------------------------------------------------------------------

SCALAR_MAP = {
    "void": "c_void",
    "bool": "bool",
    "char": "c_char",
    "int": "c_int",
    "unsigned int": "c_uint",
    "long": "c_long",
    "unsigned long": "c_ulong",
    "intptr_t": "isize",
    "uintptr_t": "usize",
    "size_t": "usize",
    "ptrdiff_t": "isize",
    "int8_t": "i8",
    "uint8_t": "u8",
    "int16_t": "i16",
    "uint16_t": "u16",
    "int32_t": "i32",
    "uint32_t": "u32",
    "int64_t": "i64",
    "uint64_t": "u64",
    "float": "f32",
    "double": "f64",
}

# Types whose Rust name is the same as the C name and which the generator emits
# itself (opaque handles, typedef'd scalars, structs).
GHOSTTY_TYPE_RE = re.compile(r"Ghostty[A-Za-z0-9_]*")

# Rust keywords that appear as C parameter/field names in these headers; they
# are emitted as raw identifiers so the C name is preserved verbatim.
RUST_KEYWORDS = {
    "as", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
    "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
    "move", "mut", "pub", "ref", "return", "self", "static", "struct", "super",
    "trait", "true", "type", "unsafe", "use", "where", "while", "abstract",
    "become", "box", "do", "final", "macro", "override", "priv", "typeof",
    "unsized", "virtual", "yield", "try", "union", "async", "await",
}

# Raw identifiers cannot be used for these.
NON_RAW_KEYWORDS = {"crate", "self", "super", "Self"}


def safe_ident(name: str) -> str:
    """Return `name` as a usable Rust identifier."""
    if name in NON_RAW_KEYWORDS:
        return f"{name}_"
    if name in RUST_KEYWORDS:
        return f"r#{name}"
    return name

# Headers to parse, in the order the umbrella header includes them. Parsing
# order only affects comments; Rust items are order independent.
INCLUDE_RE = re.compile(r'#include\s+<(ghostty/vt/[^>]+)>')


@dataclass
class Skipped:
    reason: str
    source: str


@dataclass
class Emitted:
    functions: dict[str, str] = field(default_factory=dict)
    types: dict[str, str] = field(default_factory=dict)
    consts: dict[str, str] = field(default_factory=dict)
    skipped: list[Skipped] = field(default_factory=list)
    fn_ptrs: dict[str, str] = field(default_factory=dict)
    forward_tags: set[str] = field(default_factory=set)


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


def map_type(c_type: str) -> str:
    """Translate one C declaration specifier list into Rust."""
    t = " ".join(c_type.split())
    t = t.replace("GHOSTTY_ENUM_TYPED", "").strip()
    t = t.replace("GHOSTTY_API", "").strip()
    t = t.replace("static", "").strip()
    t = re.sub(r"\brestrict\b", "", t).strip()
    # Drop the windows export/import specifiers if ever seen.
    t = re.sub(r"\b__declspec\([^)]*\)", "", t).strip()
    t = re.sub(r"\b__attribute__\(\([^)]*\)\)", "", t).strip()

    # Peel array suffixes: int x[4] -> type int, dims [4]
    dims: list[str] = []
    m = re.search(r"((?:\s*\[\s*[^\]]*\s*\])+)$", t)
    if m:
        dims = [d.strip("[] \t") for d in re.findall(r"\[([^\]]*)\]", m.group(1))]
        t = t[: m.start()].strip()
    for dim in reversed(dims):
        t = f"{t}[{dim}]"

    is_const = bool(re.search(r"\bconst\b", t))
    stars = t.count("*")
    base = re.sub(r"\bconst\b|\brestrict\b", " ", t).replace("*", " ").strip()
    base = " ".join(base.split())

    if base in SCALAR_MAP:
        rust = SCALAR_MAP[base]
    elif GHOSTTY_TYPE_RE.fullmatch(base):
        rust = base
    elif base in ("", "void"):
        rust = "c_void"
    else:
        raise ValueError(f"unmapped C type: {base!r}")

    # `const` attaches to whatever it precedes; treat any const as pointee const.
    for _ in range(stars):
        rust = f"*const {rust}" if is_const else f"*mut {rust}"
    return rust


def parse_field(decl: str) -> tuple[str, str] | None:
    """Parse a struct/union member declaration into (rust_type, rust_name)."""
    decl = decl.strip()
    if not decl:
        return None
    # Function pointer member: ret (*name)(params)
    m = re.search(r"\(\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\((.*)\)\s*$", decl, re.S)
    if m:
        name, params = m.group(1), m.group(2)
        rust = fn_ptr_type(decl[: m.start()], params)
        return rust, name

    m = re.match(r"^(.*?)([A-Za-z_][A-Za-z0-9_]*)\s*((?:\[\s*[^\]]*\s*\])*)\s*$", decl, re.S)
    if not m:
        raise ValueError(f"unparsed member: {decl!r}")
    type_part, name, dims = m.group(1), m.group(2), m.group(3)
    rust = map_type(type_part)
    if dims:
        sizes = [d.strip("[] \t") for d in re.findall(r"\[([^\]]*)\]", dims)]
        inner = rust
        for size in reversed(sizes):
            inner = f"[{inner}; {size}]"
        rust = inner
    return rust, name


def fn_ptr_type(ret: str, params: str) -> str:
    rust_ret = map_type(ret) if ret.strip() else "c_void"
    args = []
    for part in split_top_level(params):
        part = part.strip()
        if not part or part == "void":
            continue
        parsed = parse_field(part)
        if parsed is None:
            continue
        args.append(parsed[0])
    joined = ", ".join(args)
    if rust_ret == "c_void":
        return f"Option<unsafe extern \"C\" fn({joined})>"
    return f"Option<unsafe extern \"C\" fn({joined}) -> {rust_ret}>"


# ---------------------------------------------------------------------------
# Header parsing
# ---------------------------------------------------------------------------


def parse_header(path: str, out: Emitted) -> None:
    raw = open(path, encoding="utf-8").read()
    src = strip_comments(raw)
    rel = os.path.relpath(path, REPO_ROOT)
    src, guarded = strip_target_guards(src)
    for gname in guarded:
        out.skipped.append(
            Skipped("declared only under `#ifdef __wasm__`", f"{rel}: {gname}")
        )

    # --- object-like macros -------------------------------------------------
    for m in re.finditer(
        r"^#define\s+(GHOSTTY_[A-Z0-9_]+)\s+([^(\n].*?)\s*$", src, re.M
    ):
        name, value = m.group(1), m.group(2).strip()
        value = value.replace("GHOSTTY_ENUM_MAX_VALUE", "c_int::MAX")
        # Trailing // already stripped; reject function-like or complex bodies.
        if re.fullmatch(r"[-+0-9xXa-fA-F\s()<>|&~]*", value) and value:
            out.consts[name] = f"pub const {name}: c_int = {value};"

    # --- typedefs -----------------------------------------------------------
    for m in re.finditer(r"\btypedef\b", src):
        start = m.start()
        try:
            end = find_decl_end(src, start)
        except ValueError:
            continue
        decl = src[start:end]
        has_body = "{" in decl
        if "(" in decl and "(*" not in decl and not has_body:
            # Function typedef without a pointer, e.g. `typedef void f(void)`
            out.skipped.append(Skipped("function typedef (non-pointer)", rel))
            continue

        # enum
        em = re.match(
            r"typedef\s+enum\s*(?:GHOSTTY_ENUM_TYPED\s*)?\{(?P<body>.*)\}\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*$",
            decl,
            re.S,
        )
        if em:
            emit_enum(em.group("name"), em.group("body"), rel, out)
            continue

        # struct / union with body
        sm = re.match(
            r"typedef\s+(?P<kind>struct|union)\s*(?P<tag>[A-Za-z_][A-Za-z0-9_]*)?\s*\{(?P<body>.*)\}\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*$",
            decl,
            re.S,
        )
        if sm:
            emit_record(
                sm.group("kind"), sm.group("name"), sm.group("body"), rel, out
            )
            continue

        # opaque handle: typedef struct XImpl* X;  /  typedef const struct XImpl* X;
        om = re.match(
            r"typedef\s+(?P<const>const\s+)?struct\s+(?P<tag>[A-Za-z_][A-Za-z0-9_]*)\s*\*\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*$",
            decl,
            re.S,
        )
        if om:
            tag = om.group("tag")
            name = om.group("name")
            out.types[tag] = (
                f"/// Opaque C type backing the `{name}` handle.\n"
                f"#[derive(Clone, Copy)]\n"
                f"#[repr(C)]\n"
                f"pub struct {tag} {{\n"
                f"    _private: [u8; 0],\n"
                f"}}"
            )
            ptr = f"*const {tag}" if om.group("const") else f"*mut {tag}"
            out.types[name] = f"pub type {name} = {ptr};"
            continue

        # function pointer typedef (never brace-bearing; those are records)
        fm = None
        if not has_body:
            fm = re.match(
                r"typedef\s+(?P<ret>.*?)\(\s*\*\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\((?P<params>.*)\)\s*$",
                decl,
                re.S,
            )
        if fm:
            name = fm.group("name")
            try:
                out.fn_ptrs[name] = (
                    f"pub type {name} = {fn_ptr_type(fm.group('ret'), fm.group('params'))};"
                )
            except ValueError as exc:
                out.skipped.append(Skipped(str(exc), f"{rel}: {name}"))
            continue

        # forward typedef of a later-defined tagged record:
        #   typedef struct GhosttyFoo GhosttyFoo;
        fwd = re.match(
            r"typedef\s+(?P<kind>struct|union)\s+(?P<tag>[A-Za-z_][A-Za-z0-9_]*)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*$",
            decl,
            re.S,
        )
        if fwd:
            if fwd.group("tag") != fwd.group("name"):
                out.types[fwd.group("name")] = (
                    f"pub type {fwd.group('name')} = {fwd.group('tag')};"
                )
            out.forward_tags.add(fwd.group("tag"))
            continue

        # plain alias: typedef uint16_t GhosttyMods;
        am = re.match(
            r"typedef\s+(?P<type>.+?)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*$",
            decl,
            re.S,
        )
        if am:
            try:
                rust = map_type(am.group("type"))
            except ValueError as exc:
                out.skipped.append(Skipped(str(exc), f"{rel}: {decl.strip()}"))
                continue
            out.types[am.group("name")] = f"pub type {am.group('name')} = {rust};"
            continue

        out.skipped.append(Skipped("unrecognised typedef", f"{rel}: {decl.strip()}"))

    # --- bare tagged record definitions (no typedef) ------------------------
    for m in re.finditer(r"(?<![A-Za-z0-9_])struct\s+[A-Za-z_][A-Za-z0-9_]*\s*\{", src):
        start = m.start()
        brace = src.index("{", start)
        try:
            end = find_decl_end(src, start)
        except ValueError:
            continue
        decl = src[start:end]
        tm = re.match(r"struct\s+(?P<tag>[A-Za-z_][A-Za-z0-9_]*)\s*\{(?P<body>.*)\}\s*$", decl, re.S)
        if not tm:
            continue
        emit_record("struct", tm.group("tag"), tm.group("body"), rel, out)

    # --- exported functions -------------------------------------------------
    for m in re.finditer(r"GHOSTTY_API\s", src):
        start = m.start()
        line_start = src.rfind("\n", 0, start) + 1
        if "#" in src[line_start:start]:
            # e.g. `#define GHOSTTY_API ...` in types.h
            continue
        try:
            end = find_decl_end(src, start)
        except ValueError:
            continue
        decl = src[start:end]
        decl = decl.replace("GHOSTTY_API", "").strip()
        fdecl = re.match(
            r"^(?P<ret>.+?)\s*(?P<name>ghostty_[A-Za-z0-9_]+)\s*\((?P<params>.*)\)\s*$",
            " ".join(decl.split()),
            re.S,
        )
        if not fdecl:
            out.skipped.append(Skipped("unparsed function", f"{rel}: {decl.strip()}"))
            continue
        name = fdecl.group("name")
        try:
            rust_ret = map_type(fdecl.group("ret"))
            params = []
            for part in split_top_level(fdecl.group("params")):
                part = part.strip()
                if not part or part == "void":
                    continue
                if part == "...":
                    params.append("...")
                    continue
                parsed = parse_field(part)
                if parsed is None:
                    continue
                params.append(f"{safe_ident(parsed[1])}: {parsed[0]}")
        except ValueError as exc:
            out.skipped.append(Skipped(str(exc), f"{rel}: {name}"))
            continue
        out.functions[name] = (
            f"    pub fn {name}({', '.join(params)})"
            + (f" -> {rust_ret}" if rust_ret != "c_void" else "")
            + ";"
        )


def emit_enum(name: str, body: str, rel: str, out: Emitted) -> None:
    lines = [f"/// C enum `{name}` from `{rel}` (int-backed, per the libghostty-vt ABI)."]
    lines.append(f"pub type {name} = c_int;")
    out.types[name] = "\n".join(lines)

    values: list[tuple[str, str]] = []
    next_value = 0
    for entry in split_top_level(body):
        entry = entry.strip()
        if not entry:
            continue
        if "=" in entry:
            vname, _, value = entry.partition("=")
            vname, value = vname.strip(), value.strip()
            value = value.replace("GHOSTTY_ENUM_MAX_VALUE", "c_int::MAX")
            try:
                if re.fullmatch(r"[-+]?(0[xX][0-9a-fA-F]+|\d+)", value):
                    next_value = int(value, 0) + 1
                elif value in ("c_int::MAX", "INT_MAX"):
                    next_value = 1 << 31
                else:
                    # Non-literal initialiser we cannot evaluate; stop counting.
                    next_value = None
            except ValueError:
                next_value = None
        else:
            vname = entry
            value = str(next_value) if next_value is not None else None
            if next_value is not None:
                next_value += 1

        if value is None:
            out.skipped.append(Skipped("unresolvable enum value", f"{rel}: {vname}"))
            continue
        values.append((vname, value))

    for vname, value in values:
        out.consts[vname] = f"pub const {vname}: {name} = {value};"


def emit_record(kind: str, name: str, body: str, rel: str, out: Emitted) -> None:
    rust_kind = "struct" if kind == "struct" else "union"
    fields = []
    for decl in split_top_level(body, ";"):
        decl = decl.strip()
        if not decl:
            continue
        try:
            parsed = parse_field(decl)
        except ValueError as exc:
            out.skipped.append(Skipped(str(exc), f"{rel}: {name}.{decl}"))
            continue
        if parsed is None:
            continue
        ftype, fname = parsed
        fields.append(f"    pub {safe_ident(fname)}: {ftype},")

    doc = f"/// C {kind} `{name}` from `{rel}`."
    # Every libghostty-vt value type is plain-old-data (scalars, raw pointers,
    # function pointers, and nested POD), so `Copy` is safe and is required for
    # the union payloads to be usable as union fields.
    out.types[name] = "\n".join(
        [doc, "#[derive(Clone, Copy)]", "#[repr(C)]", f"pub {rust_kind} {name} {{", *fields, "}"]
    )


# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------


def header_paths() -> list[str]:
    if not os.path.exists(UMBRELLA):
        raise SystemExit(f"umbrella header not found: {UMBRELLA}")
    umbrella = open(UMBRELLA, encoding="utf-8").read()
    ordered = INCLUDE_RE.findall(umbrella)
    paths = []
    for rel in ordered:
        path = os.path.join(INCLUDE_DIR, rel)
        if os.path.exists(path):
            paths.append(path)
    # Anything the umbrella does not include is still worth binding.
    for root, _dirs, files in os.walk(os.path.join(INCLUDE_DIR, "ghostty", "vt")):
        for fname in sorted(files):
            if fname.endswith(".h"):
                path = os.path.join(root, fname)
                if path not in paths:
                    paths.append(path)
    return paths


def generate() -> tuple[str, Emitted]:
    out = Emitted()
    for path in header_paths():
        parse_header(path, out)

    total_declared = 0
    for path in header_paths():
        body = strip_comments(open(path, encoding="utf-8").read())
        body, _ = strip_target_guards(body)
        total_declared += len(re.findall("GHOSTTY_API ", body))

    parts: list[str] = []
    parts.append(
        """//! Raw `extern "C"` bindings for `libghostty-vt`.
//!
//! **Generated file.** Regenerate with `python3 tools/gen_ffi.py` from the
//! Khostty checkout (`include/ghostty/vt.h` plus `include/ghostty/vt/**`).
//! Do not edit by hand: `tests/ffi_coverage.rs` fails if this file drifts from
//! the C headers.
//!
//! Every declaration below is transcribed from the C headers by
//! `tools/gen_ffi.py`; the generator reports anything it could not represent in
//! the `SKIPPED` section at the bottom rather than dropping it silently.
//!
//! # Safety
//!
//! These are the *raw* bindings. Calling them directly requires upholding the
//! invariants documented in the corresponding C header: live handles must not
//! be double-freed, borrowed pointers (`GhosttyString`, row/cell `RAW` values,
//! search match buffers) are only valid until the next mutating call on the
//! object that produced them, and callbacks must not unwind across the FFI
//! boundary. Prefer the safe wrappers in [`crate::terminal`], [`crate::snapshot`],
//! [`crate::render`], [`crate::search`], [`crate::key`] and [`crate::mouse`].
//!
//! C enums are `int`-backed in this ABI (see the `GHOSTTY_ENUM_TYPED` comment
//! in `types.h`), so each C enum is a `c_int` type alias with `pub const`
//! values. That avoids relying on Rust enum layout and keeps unknown values
//! representable when a newer library returns a code this binding predates.

#![allow(
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals,
    dead_code,
    clippy::missing_safety_doc,
    clippy::too_many_arguments
)]


{ffi_imports}
"""
    )

    parts.append(
        f"// ---------------------------------------------------------------------\n"
        f"// Coverage: {len(out.functions)} functions, {len(out.types)} types, "
        f"{len(out.consts)} constants\n"
        f"// declared across {len(header_paths())} headers "
        f"({total_declared} `GHOSTTY_API` declarations detected).\n"
        f"// ---------------------------------------------------------------------\n"
    )

    parts.append(f"/// Number of `GHOSTTY_API` functions declared by this binding.\npub const BINDING_FUNCTION_COUNT: usize = {len(out.functions)};\n")

    if out.consts:
        parts.append("// ---- Constants ---------------------------------------------------------\n")
        for name in sorted(out.consts):
            parts.append(out.consts[name])
        parts.append("")

    if out.types:
        parts.append("// ---- Types -------------------------------------------------------------\n")
        for name in sorted(out.types):
            parts.append(out.types[name])
        parts.append("")

    if out.fn_ptrs:
        parts.append("// ---- Callback types ----------------------------------------------------\n")
        for name in sorted(out.fn_ptrs):
            parts.append(out.fn_ptrs[name])
        parts.append("")

    parts.append("// ---- Exported functions ------------------------------------------------\n")
    parts.append('extern "C" {')
    for name in sorted(out.functions):
        parts.append(out.functions[name])
    parts.append("}")
    parts.append("")

    if out.skipped:
        parts.append("// ---- SKIPPED -----------------------------------------------------------\n")
        parts.append("// Items the generator could not represent as Rust declarations:\n")
        for skip in sorted(set((s.reason, s.source) for s in out.skipped)):
            parts.append(f"//   - {skip[0]}: {skip[1]}")
        parts.append("")

    text = "\n".join(parts)
    need = [
        name
        for name in ("c_char", "c_int", "c_long", "c_uint", "c_ulong", "c_void")
        if re.search(r"\b" + name + r"\b", text)
    ]
    ffi_imports = "use core::ffi::{" + ", ".join(need) + "};" if need else ""
    text = text.replace("{ffi_imports}", ffi_imports)
    return text + "\n", out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 if stale")
    args = ap.parse_args()

    text, out = generate()

    if args.check:
        existing = open(OUT_PATH, encoding="utf-8").read() if os.path.exists(OUT_PATH) else ""
        if existing != text:
            print("src/ffi.rs is stale; run tools/gen_ffi.py", file=sys.stderr)
            return 1
        print("src/ffi.rs is up to date")
        return 0

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        fh.write(text)

    print(
        f"wrote {OUT_PATH}: {len(text.splitlines())} lines, "
        f"{len(out.functions)} functions, {len(out.types)} types, "
        f"{len(out.consts)} constants, {len(out.skipped)} skipped"
    )
    for reason, source in sorted(set((s.reason, s.source) for s in out.skipped)):
        print(f"  skipped {reason}: {source}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
