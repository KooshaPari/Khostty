#!/usr/bin/env python3
"""K-E03: compare an out-of-tree Rust wrapper consumer with direct C upstream API use.

This harness is fail-closed: a missing native library must fail the Rust build.
It records exact source/library identities and executes both consumers. It does
not claim the wrapper is preferable; that decision requires reviewing the receipt.
"""
from __future__ import annotations
import argparse, hashlib, json, os, platform, shutil, subprocess, tempfile
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd, *, cwd=None, env=None, timeout=180):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    return {"cmd": cmd, "returncode": p.returncode, "stdout": p.stdout, "stderr": p.stderr}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crate-dir", type=Path, required=True)
    ap.add_argument("--include-dir", type=Path, required=True)
    ap.add_argument("--lib", type=Path, required=True)
    ap.add_argument("--source-sha", required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    crate = a.crate_dir.resolve()
    include = a.include_dir.resolve()
    lib = a.lib.resolve()
    if not lib.is_file():
        raise SystemExit(f"native library missing: {lib}")
    for tool in ("cargo", "cc"):
        if not shutil.which(tool):
            raise SystemExit(f"required tool missing: {tool}")

    with tempfile.TemporaryDirectory(prefix="k-e03-") as td:
        root = Path(td)
        rust = root / "rust"; rust.mkdir()
        (rust / "src").mkdir()
        crate_toml = str(crate).replace("\\", "\\\\").replace('"', '\\"')
        (rust / "Cargo.toml").write_text(
            '[package]\nname="k_e03_consumer"\nversion="0.0.0"\nedition="2021"\n'
            f'\n[dependencies]\nkhostty-vt={{path="{crate_toml}"}}\n'
        )
        (rust / "src/main.rs").write_text(
            'fn main() -> Result<(), khostty_vt::GhosttyError> {\n'
            '  let mut t = khostty_vt::Terminal::new(20, 4)?;\n'
            '  t.vt_write(b"K-E03\\r\\n");\n'
            '  println!("linked-ok");\n'
            '  Ok(())\n'
            '}\n'
        )
        env = os.environ.copy()
        env["GHOSTTY_VT_LIB"] = str(lib)
        env["KHOSTTY_VT_REQUIRE_LINK"] = "1"
        env["CARGO_TARGET_DIR"] = str(root / "target-linked")
        rust_run = run(["cargo", "run", "--quiet"], cwd=rust, env=env)

        # Prove the fail-closed control separately with a fresh target dir.
        bad = env.copy()
        bad["GHOSTTY_VT_LIB"] = str(root / "definitely-missing-libghostty-vt.so")
        bad["GHOSTTY_VT_LIB_DIR"] = str(root / "also-missing")
        bad["CARGO_TARGET_DIR"] = str(root / "target-missing")
        rust_missing = run(["cargo", "check", "--quiet"], cwd=rust, env=bad)

        csrc = root / "direct.c"
        csrc.write_text(
            '#include <ghostty/vt.h>\n#include <stdint.h>\n#include <stdio.h>\n'
            'int main(void) { GhosttyTerminal t = NULL; '
            'if (ghostty_terminal_new(NULL, &t, 20, 4) != GHOSTTY_SUCCESS) return 2; '
            'const uint8_t b[] = "K-E03\\r\\n"; ghostty_terminal_vt_write(t,b,sizeof(b)-1); '
            'ghostty_terminal_free(t); puts("linked-ok"); return 0; }\n'
        )
        exe = root / "direct"
        libdir = lib.parent
        cbuild = run(["cc", str(csrc), "-I", str(include), "-L", str(libdir),
                      "-lghostty-vt", f"-Wl,-rpath,{libdir}", "-o", str(exe)])
        crun = run([str(exe)]) if cbuild["returncode"] == 0 else {
            "cmd": [str(exe)], "returncode": None, "stdout": "", "stderr": "compile failed"
        }

        checks = {
            "rust_linked_consumer_executed": rust_run["returncode"] == 0 and "linked-ok" in rust_run["stdout"],
            "missing_library_fails_closed": rust_missing["returncode"] != 0,
            "direct_c_consumer_executed": crun["returncode"] == 0 and "linked-ok" in crun["stdout"],
        }
        receipt = {
            "schema_version": 1,
            "subject": "K-E03_WRAPPER_VS_DIRECT_C_EXPERIMENT",
            "source_sha": a.source_sha,
            "crate_dir": str(crate),
            "include_dir": str(include),
            "native_library": str(lib),
            "native_library_sha256": sha256(lib),
            "platform": platform.platform(),
            "checks": checks,
            "rust_linked": rust_run,
            "rust_missing_library_control": rust_missing,
            "direct_c_build": cbuild,
            "direct_c_run": crun,
            "verdict": "PASS_EXPERIMENT" if all(checks.values()) else "FAIL_EXPERIMENT",
            "limitations": [
                "This proves a minimal linked consumer, not all wrapper APIs.",
                "Safety/unsafe LOC, ABI drift, snapshot/search and packaging metrics require follow-up.",
                "The direct C comparator uses the same supplied native library artifact."
            ],
        }
        a.out.parent.mkdir(parents=True, exist_ok=True)
        with a.out.open("x") as f:
            json.dump(receipt, f, indent=2); f.write("\n")
        print(json.dumps(receipt, indent=2))
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
