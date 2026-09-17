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

This file owns header discovery and Rust emission. Scanning C text lives in
`cscan.py` and the C-to-Rust type mapping plus the emitted-item model live in
`cabitypes.py`; the three were one file until it outgrew the repository's
file-size budget.

Usage:
    python3 tools/gen_ffi.py            # rewrite src/ffi.rs
    python3 tools/gen_ffi.py --check    # exit 1 if src/ffi.rs is stale
"""
from __future__ import annotations

import argparse
import os
import re
import sys

from cabitypes import Emitted, Skipped, fn_ptr_type, map_type, parse_field, safe_ident
from cscan import (
    INCLUDE_RE,
    find_decl_end,
    split_top_level,
    strip_comments,
    strip_redundant_outer_parens,
    strip_target_guards,
)

HERE = os.path.dirname(os.path.abspath(__file__))
CRATE_ROOT = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(CRATE_ROOT)
INCLUDE_DIR = os.path.join(REPO_ROOT, "include")
UMBRELLA = os.path.join(INCLUDE_DIR, "ghostty", "vt.h")
OUT_PATH = os.path.join(CRATE_ROOT, "src", "ffi.rs")



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
    # Requiring whitespace after the macro name excludes function-like macros
    # (`#define FOO(x) ...`), while still accepting parenthesised bodies such as
    # `#define GHOSTTY_MODS_SHIFT (1 << 0)`.
    for m in re.finditer(
        r"^#define\s+(GHOSTTY_[A-Z0-9_]+)\s+([^\n].*?)\s*$", src, re.M
    ):
        name, value = m.group(1), m.group(2).strip()
        value = value.replace("GHOSTTY_ENUM_MAX_VALUE", "c_int::MAX")
        value = strip_redundant_outer_parens(value)
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
