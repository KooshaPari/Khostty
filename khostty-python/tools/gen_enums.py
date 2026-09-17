#!/usr/bin/env python3
"""Regenerate ``khostty_vt/_enums_gen.py`` from the library's type manifest.

The GhosttyKey enum has 176 selectable members. Transcribing them by hand would
be tedious and easy to get subtly wrong, so they are derived from the library's
own ``ghostty_type_json()`` output instead. Run from ``khostty-python``::

    python tools/gen_enums.py

The output is checked in, and ``tests/test_key.py`` re-derives every value from
the manifest so a stale table fails the suite rather than selecting the wrong
key.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from khostty_vt import _ffi  # noqa: E402

# The enums worth generating: large, purely mechanical, and easy to get wrong.
GENERATED = {"Keys": "GhosttyKey"}

HEADER = '''"""Physical key codes, generated from libghostty-vt's own type manifest.

DO NOT EDIT. Regenerate with::

    python tools/gen_enums.py

The values come from the linked library, so they always match the build these
bindings are used with. ``khostty_vt.validate_enum_values`` re-derives them, so
a stale table is reported rather than silently selecting the wrong key.
"""

from __future__ import annotations

from enum import IntEnum

__all__ = ["Keys"]


'''


def main() -> int:
    types = _ffi.type_manifest()["types"]

    blocks = []
    for class_name, c_name in GENERATED.items():
        entry = types[c_name]
        values = {
            name: value for name, value in entry["values"].items() if not name.endswith("MAX_VALUE")
        }
        lines = [
            f"class {class_name}(IntEnum):",
            '    """Physical key codes, mirroring GhosttyKey."""',
            "",
        ]
        for name, value in sorted(values.items(), key=lambda item: item[1]):
            lines.append(f"    {name} = {value}")
        blocks.append("\n".join(lines) + "\n")

    output = HEADER + "\n\n".join(blocks)
    target = ROOT / "khostty_vt" / "_enums_gen.py"
    target.write_text(output)
    print(f"wrote {target.relative_to(ROOT)} ({len(output.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
