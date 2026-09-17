#!/usr/bin/env python3
"""C-to-Rust type mapping and the model of emitted binding items.

This is the layer between raw C declaration text and Rust syntax: what
`const GhosttyAllocator*` becomes, how array members and function-pointer
typedefs are spelled, which C names are Rust keywords, and what a parsed
declaration contributes to the generated file.

Split out of `gen_ffi.py` because mapping types and emitting Rust are
separate concerns, and the combined file exceeded the repository's size
budget.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from cscan import split_top_level

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


