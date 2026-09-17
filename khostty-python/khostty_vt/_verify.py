"""Runtime ABI verification against the library's own type manifest.

The cffi declarations in :mod:`khostty_vt._cdef` and the enum values in
:mod:`khostty_vt.constants` were written against one build of
``libghostty-vt``. Both are re-derived from the linked library here, so a
mismatched pair of bindings and binary is reported as a concrete list of
disagreeing fields rather than as silent misbehaviour.

Call :func:`validate_abi` after pointing the bindings at a library that may
differ from the one they were written for.
"""

from __future__ import annotations

from typing import Any, Dict, Tuple

from . import _ffi
from .constants import (
    CursorShape,
    FormatterFormat,
    Result,
    Screen,
    SearchData,
    SearchOption,
    SearchScroll,
    SearchStatus,
    StyleColorKind,
    TerminalData,
    TerminalOption,
    Underline,
)

__all__ = ["ENUM_TYPES", "validate_abi", "validate_enum_values"]

#: Python enum class to the C enum name in the type manifest.
ENUM_TYPES: Dict[type, str] = {
    Result: "GhosttyResult",
    TerminalData: "GhosttyTerminalData",
    TerminalOption: "GhosttyTerminalOption",
    Screen: "GhosttyTerminalScreen",
    CursorShape: "GhosttyTerminalCursorStyle",
    FormatterFormat: "GhosttyFormatterFormat",
    SearchData: "GhosttySearchData",
    SearchOption: "GhosttySearchOption",
    SearchStatus: "GhosttySearchStatus",
    SearchScroll: "GhosttySearchScroll",
    StyleColorKind: "GhosttyStyleColorTag",
    Underline: "GhosttySgrUnderline",
}


def validate_enum_values() -> Dict[str, Dict[str, Tuple[int, int]]]:
    """Compare every declared enum member against the library manifest.

    The comparison is bidirectional: a member the library has but the Python
    enum does not (or vice versa) is a mismatch, because either direction means
    a value exists that one side cannot name.

    Returns:
        ``{enum_name: {member_name: (declared, library)}}`` for each member
        that disagrees or is missing on one side. ``-1`` marks an absent
        member. An empty mapping means the constants match the linked library.
    """
    types = _ffi.type_manifest().get("types", {})
    mismatches: Dict[str, Dict[str, Tuple[int, int]]] = {}

    for enum_cls, c_name in ENUM_TYPES.items():
        entry = types.get(c_name)
        if entry is None:
            mismatches[c_name] = {"<enum type>": (-1, -1)}
            continue
        # The manifest strips the C prefix, so members compare by bare name.
        library_values = entry.get("values", {})
        for member in enum_cls:
            actual = library_values.get(member.name)
            if actual is None:
                mismatches.setdefault(c_name, {})[member.name] = (int(member), -1)
            elif int(actual) != int(member):
                mismatches.setdefault(c_name, {})[member.name] = (int(member), int(actual))

        # Anything the library names that the bindings do not is also drift:
        # a caller cannot select it, and a future default could move onto it.
        # Sentinel members carry no selectable value and are ignored.
        declared = {member.name for member in enum_cls}
        for name in library_values:
            if name.endswith("MAX_VALUE") or name in declared:
                continue
            mismatches.setdefault(c_name, {})[name] = (-1, int(library_values[name]))
    return mismatches


def validate_abi(check_enums: bool = True) -> Dict[str, Any]:
    """Check declarations and constants against the linked library.

    Args:
        check_enums: Also compare enum members, not just struct sizes.

    Returns:
        A report with two keys, ``struct_sizes`` and ``enum_values``, each
        holding the disagreements found. Both empty means the bindings match
        the library. ``library_version`` records which library was checked, so
        a stored report stays interpretable.
    """
    manifest = _ffi.type_manifest()
    report: Dict[str, Any] = {
        "library_version": manifest.get("library_version", ""),
        "library_path": _ffi.library_path(),
        "struct_sizes": _ffi.validate_struct_sizes(),
        "enum_values": validate_enum_values() if check_enums else {},
    }
    report["ok"] = not report["struct_sizes"] and not report["enum_values"]
    return report
