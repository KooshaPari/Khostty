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
    ap.add_argument("--library-source-sha", required=True,
                    help="source revision that produced --lib; evidence only, not cryptographically authenticated")
    ap.add_argument("--library-origin", choices=("khostty", "upstream-ghostty"), required=True)
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
            'use khostty_vt::{RenderState, Search, SnapshotDecoder, Terminal, encode_snapshot};\n'
            'fn main() -> Result<(), khostty_vt::GhosttyError> {\n'
            '  let mut t = Terminal::new(20, 4)?;\n'
            '  t.vt_write(b"K-E03\\r\\nneedle\\r\\n");\n'
            '  t.resize(24, 6, 8, 16)?;\n'
            '  if t.cols()? != 24 || t.rows()? != 6 { panic!("resize did not stick"); }\n'
            '  let mut render = RenderState::new()?; render.update(&t)?;\n'
            '  if render.cols()? != 24 || render.rows_count()? != 6 { panic!("render dimensions wrong"); }\n'
            '  let mut search = Search::new(&t)?; search.set_needle(&t, "needle")?; search.run(&t)?;\n'
            '  if search.total_matches()? < 1 { panic!("search did not find fixture"); }\n'
            '  drop(search);\n'
            '  let snapshot = encode_snapshot(&t)?;\n'
            '  let restored = SnapshotDecoder::from_bytes(&snapshot)?.decode()?;\n'
            '  if restored.cols()? != 24 || restored.rows()? != 6 { panic!("snapshot restore wrong"); }\n'
            '  println!("linked-ok resize-render-search-snapshot");\n'
            '  Ok(())\n'
            '}\n'
        )
        env = os.environ.copy()
        env["GHOSTTY_VT_LIB"] = str(lib)
        env["KHOSTTY_VT_LINK_KIND"] = "static" if lib.suffix == ".a" else "dylib"
        env["KHOSTTY_VT_REQUIRE_LINK"] = "1"
        env["CARGO_TARGET_DIR"] = str(root / "target-linked")
        # Cargo dependency build-script rpath arguments do not reliably propagate\n        # to an out-of-tree downstream binary. Configure the native loader\n        # explicitly for the execution witness and record that deployment burden.\n        loader_var = "DYLD_LIBRARY_PATH" if platform.system() == "Darwin" else "LD_LIBRARY_PATH"\n        prior_loader = env.get(loader_var, "")\n        env[loader_var] = str(lib.parent) + (os.pathsep + prior_loader if prior_loader else "")\n        rust_run = run(["cargo", "run", "--quiet"], cwd=rust, env=env)

        # Compile-fail ownership control: a Search borrows terminal identity through
        # its API contract; Rust must not allow the terminal to be moved/dropped
        # while a later search operation still needs it. This is safer evidence
        # than deliberately dereferencing a freed native handle.
        lifetime = root / "rust-lifetime"; lifetime.mkdir(); (lifetime / "src").mkdir()
        (lifetime / "Cargo.toml").write_text(
            '[package]\nname="k_e03_lifetime"\nversion="0.0.0"\nedition="2021"\n'
            f'\n[dependencies]\nkhostty-vt={{path="{crate_toml}"}}\n'
        )
        (lifetime / "src/main.rs").write_text(
            'use khostty_vt::{Search, Terminal};\n'
            'fn main() -> Result<(), khostty_vt::GhosttyError> {\n'
            ' let t = Terminal::new(20,4)?; let mut s = Search::new(&t)?;\n'
            ' drop(t); s.set_needle(&t, "x")?; Ok(()) }\n'
        )
        lifetime_env = env.copy(); lifetime_env["CARGO_TARGET_DIR"] = str(root / "target-lifetime")
        lifetime_compile = run(["cargo", "check", "--quiet"], cwd=lifetime, env=lifetime_env)

        # Prove the fail-closed control separately with a fresh target dir.
        bad = env.copy()
        bad["GHOSTTY_VT_LIB"] = str(root / "definitely-missing-libghostty-vt.so")
        bad["GHOSTTY_VT_LIB_DIR"] = str(root / "also-missing")
        bad["CARGO_TARGET_DIR"] = str(root / "target-missing")
        rust_missing = run(["cargo", "check", "--quiet"], cwd=rust, env=bad)

        csrc = root / "direct.c"
        csrc.write_text(
            '#include <ghostty/vt.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n'
            '#define OK(x) do { if ((x) != GHOSTTY_SUCCESS) return __LINE__; } while (0)\n'
            'int main(void) {\n'
            ' GhosttyTerminal t = NULL; OK(ghostty_terminal_new(NULL, &t, 20, 4));\n'
            ' const uint8_t input[] = "K-E03\\r\\nneedle\\r\\n"; ghostty_terminal_vt_write(t,input,sizeof(input)-1);\n'
            ' OK(ghostty_terminal_resize(t,24,6,8,16)); uint16_t cols=0,rows=0;\n'
            ' OK(ghostty_terminal_get(t,GHOSTTY_TERMINAL_DATA_COLS,&cols)); OK(ghostty_terminal_get(t,GHOSTTY_TERMINAL_DATA_ROWS,&rows));\n'
            ' if (cols != 24 || rows != 6) return 30;\n'
            ' GhosttyRenderState rs=NULL; OK(ghostty_render_state_new(NULL,&rs)); OK(ghostty_render_state_update(rs,t));\n'
            ' uint16_t rcols=0,rrows=0; OK(ghostty_render_state_get(rs,GHOSTTY_RENDER_STATE_DATA_COLS,&rcols)); OK(ghostty_render_state_get(rs,GHOSTTY_RENDER_STATE_DATA_ROWS,&rrows));\n'
            ' if (rcols != 24 || rrows != 6) return 31; ghostty_render_state_free(rs);\n'
            ' GhosttySearch s=NULL; OK(ghostty_search_new(NULL,&s,t)); const uint8_t needle_bytes[]="needle"; GhosttyString needle={needle_bytes,sizeof(needle_bytes)-1};\n'
            ' OK(ghostty_search_set(s,GHOSTTY_SEARCH_OPT_NEEDLE,&needle)); OK(ghostty_search_run(s)); size_t matches=0; OK(ghostty_search_get(s,GHOSTTY_SEARCH_DATA_TOTAL_MATCHES,&matches));\n'
            ' if (matches < 1) return 32; ghostty_search_free(s);\n'
            ' size_t snap_len=0; GhosttyResult sr=ghostty_snapshot_encode_buf(t,NULL,0,&snap_len); if (sr != GHOSTTY_OUT_OF_SPACE || snap_len == 0) return 33;\n'
            ' uint8_t *snap=(uint8_t*)malloc(snap_len); if(!snap) return 34; OK(ghostty_snapshot_encode_buf(t,snap,snap_len,&snap_len));\n'
            ' GhosttySnapshotDecoder dec=NULL; OK(ghostty_snapshot_decoder_new_buf(NULL,&dec,snap,snap_len)); GhosttyTerminal restored=NULL; OK(ghostty_snapshot_decoder_decode(dec,&restored));\n'
            ' uint16_t restored_cols=0; OK(ghostty_terminal_get(restored,GHOSTTY_TERMINAL_DATA_COLS,&restored_cols)); if(restored_cols != 24) return 35;\n'
            ' ghostty_snapshot_decoder_free(dec); ghostty_terminal_free(restored); free(snap); ghostty_terminal_free(t);\n'
            ' puts("linked-ok resize-render-search-snapshot"); return 0; }\n'
        )
        exe = root / "direct"
        libdir = lib.parent
        cbuild = run(["cc", str(csrc), "-I", str(include), "-L", str(libdir),
                      "-lghostty-vt", f"-Wl,-rpath,{libdir}", "-o", str(exe)])
        crun = run([str(exe)]) if cbuild["returncode"] == 0 else {
            "cmd": [str(exe)], "returncode": None, "stdout": "", "stderr": "compile failed"
        }

        # Existing ABI/coverage tests are part of the wrapper's safety claim.
        verify_env = env.copy()
        verify_env["GHOSTTY_VT_INCLUDE_DIR"] = str(include)
        verify_env["CARGO_TARGET_DIR"] = str(root / "target-verify")
        abi_verify = run(
            ["cargo", "test", "--quiet", "--test", "abi_layout", "--test", "ffi_coverage"],
            cwd=crate, env=verify_env,
        )

        wrapper_files = list((crate / "src").glob("*.rs"))
        wrapper_text = "\n".join(p.read_text(errors="replace") for p in wrapper_files)
        direct_text = csrc.read_text()
        metrics = {
            "wrapper_rust_source_files": len(wrapper_files),
            "wrapper_rust_nonblank_lines": sum(
                1 for line in wrapper_text.splitlines() if line.strip()
            ),
            "wrapper_unsafe_mentions": wrapper_text.count("unsafe"),
            "direct_c_nonblank_lines": sum(
                1 for line in direct_text.splitlines() if line.strip()
            ),
            "runtime_loader_path_required": lib.suffix != ".a",\n                "out_of_tree_rust_manifest_lines": sum(
                1 for line in (rust / "Cargo.toml").read_text().splitlines() if line.strip()
            ),
            "install_steps": [
                "provide exact native library artifact",
                "provide matching include directory",
                "set GHOSTTY_VT_LIB and KHOSTTY_VT_REQUIRE_LINK",
                "cargo run from generated out-of-tree consumer",
            ],
        }
        checks = {
            "rust_linked_consumer_executed": rust_run["returncode"] == 0 and "linked-ok resize-render-search-snapshot" in rust_run["stdout"],
            "missing_library_fails_closed": rust_missing["returncode"] != 0,
            "rust_lifetime_misuse_rejected": lifetime_compile["returncode"] != 0,
            "direct_c_consumer_executed": crun["returncode"] == 0 and "linked-ok resize-render-search-snapshot" in crun["stdout"],
            "abi_and_ffi_coverage_tests_pass": abi_verify["returncode"] == 0,
        }
        receipt = {
            "schema_version": 1,
            "subject": "K-E03_WRAPPER_VS_DIRECT_C_EXPERIMENT",
            "source_sha": a.source_sha,
            "library_source_sha_claim": a.library_source_sha,
            "library_origin_claim": a.library_origin,
            "crate_dir": str(crate),
            "include_dir": str(include),
            "native_library": str(lib),
            "native_library_sha256": sha256(lib),
            "link_kind": env["KHOSTTY_VT_LINK_KIND"],
            "platform": platform.platform(),
            "checks": checks,
            "metrics": metrics,
            "rust_linked": rust_run,
            "rust_missing_library_control": rust_missing,
            "rust_lifetime_compile_fail_control": lifetime_compile,
            "direct_c_build": cbuild,
            "direct_c_run": crun,
            "abi_and_ffi_verification": abi_verify,
            "verdict": "PASS_EXPERIMENT" if all(checks.values()) else "FAIL_EXPERIMENT",
            "limitations": [
                "This proves linked create/write/resize/render/search/snapshot-restore only, not all wrapper APIs.",
                "The LOC/unsafe counts are descriptive, not a quality score.",
                "Compile-time lifetime misuse is checked; deliberately dereferencing freed native state is not performed.",
                "The existing abi_layout/ffi_coverage tests must pass against the supplied include/library configuration.",
                "The direct C comparator uses the same supplied native library artifact.",
                "library_source_sha/library_origin are caller claims; a separate build receipt must authenticate them.",
                "A true upstream-vs-Khostty comparison requires separate runs with independently built artifacts."
            ],
        }
        a.out.parent.mkdir(parents=True, exist_ok=True)
        with a.out.open("x") as f:
            json.dump(receipt, f, indent=2); f.write("\n")
        print(json.dumps(receipt, indent=2))
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
