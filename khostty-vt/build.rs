//! Build script for `khostty-vt`.
//!
//! Two responsibilities, each independently optional:
//!
//! 1. **Linking** (feature `link`). Locate a prebuilt `libghostty-vt` and emit
//!    the linker search path, the library name, and an rpath so integration
//!    tests can find the shared object at runtime. If no library is found the
//!    script prints a warning and links nothing, which keeps `cargo check`
//!    working on machines that have not built the Zig library yet.
//! 2. **Bindgen verification** (feature `bindgen`). Regenerate Rust bindings
//!    from the C headers into `$OUT_DIR/bindings.rs` so the drift test can
//!    compare them against the checked-in `src/ffi.rs`.
//!
//! Every path is overridable so the crate works when vendored:
//!
//! | Variable                  | Meaning                                       |
//! |---------------------------|-----------------------------------------------|
//! | `GHOSTTY_VT_LIB_DIR`      | Directory containing `libghostty-vt.{dylib,so,a}` |
//! | `GHOSTTY_VT_LIB`          | Explicit full path to the library file        |
//! | `GHOSTTY_VT_INCLUDE_DIR`  | Directory containing `ghostty/vt.h`           |
//! | `GHOSTTY_VT_LINK_KIND`    | Force `dylib` or `static` linking             |
//!
//! Defaults assume the crate lives directly inside the Khostty checkout, next
//! to `zig-out/` and `include/`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

/// Candidate relative locations of the prebuilt library, in preference order.
const LIB_DIR_CANDIDATES: &[&str] = &["../zig-out/lib", "../build/lib", "../dist/lib"];

/// Candidate relative locations of the C headers, in preference order.
const INCLUDE_DIR_CANDIDATES: &[&str] = &["../include", "../zig-out/include"];

/// Library file names to probe, in preference order, for a given link kind.
fn lib_file_names(kind: &str) -> Vec<String> {
    match kind {
        "static" => vec!["libghostty-vt.a".to_string()],
        // Apple uses .dylib, everything else .so.
        _ => vec![
            "libghostty-vt.dylib".to_string(),
            "libghostty-vt.so".to_string(),
        ],
    }
}

/// The link kind to use, honouring `GHOSTTY_VT_LINK_KIND` when set.
fn requested_link_kind() -> String {
    match env::var("GHOSTTY_VT_LINK_KIND") {
        Ok(v) if v == "static" => "static".to_string(),
        _ => "dylib".to_string(),
    }
}

/// Resolve the directory holding the prebuilt library, if any.
fn find_lib_dir(manifest_dir: &Path, kind: &str) -> Option<(PathBuf, PathBuf)> {
    // 1. An explicit library path wins outright.
    if let Ok(explicit) = env::var("GHOSTTY_VT_LIB") {
        let path = PathBuf::from(explicit);
        if path.is_file() {
            let dir = path.parent()?.to_path_buf();
            return Some((dir, path));
        }
        println!(
            "cargo:warning=GHOSTTY_VT_LIB={} does not exist; falling back to directory search",
            path.display()
        );
    }

    // 2. An explicit directory.
    let mut dirs: Vec<PathBuf> = Vec::new();
    if let Ok(explicit_dir) = env::var("GHOSTTY_VT_LIB_DIR") {
        dirs.push(PathBuf::from(explicit_dir));
    }

    // 3. Repository-relative defaults.
    for candidate in LIB_DIR_CANDIDATES {
        dirs.push(manifest_dir.join(candidate));
    }

    for dir in dirs {
        for name in lib_file_names(kind) {
            let candidate = dir.join(&name);
            if candidate.is_file() {
                return Some((dir, candidate));
            }
        }
    }
    None
}

/// Resolve the directory containing `ghostty/vt.h`, if any.
fn find_include_dir(manifest_dir: &Path) -> Option<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    if let Ok(explicit) = env::var("GHOSTTY_VT_INCLUDE_DIR") {
        dirs.push(PathBuf::from(explicit));
    }
    for candidate in INCLUDE_DIR_CANDIDATES {
        dirs.push(manifest_dir.join(candidate));
    }

    dirs.into_iter()
        .find(|dir| dir.join("ghostty").join("vt.h").is_file())
}

/// Recursively collect `.h` files so Cargo re-runs when the C API changes.
fn collect_headers(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_headers(&path, out);
        } else if path.extension().is_some_and(|ext| ext == "h") {
            out.push(path);
        }
    }
}

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));

    // `rustc-check-cfg` keeps `--check-cfg` builds quiet about our custom cfgs.
    println!("cargo:rustc-check-cfg=cfg(ghostty_vt_linked)");
    println!("cargo:rustc-check-cfg=cfg(ghostty_vt_bindgen)");
    println!("cargo:rerun-if-env-changed=GHOSTTY_VT_LIB");
    println!("cargo:rerun-if-env-changed=GHOSTTY_VT_LIB_DIR");
    println!("cargo:rerun-if-env-changed=GHOSTTY_VT_INCLUDE_DIR");
    println!("cargo:rerun-if-env-changed=GHOSTTY_VT_LINK_KIND");

    if let Some(include_dir) = find_include_dir(&manifest_dir) {
        let mut headers = Vec::new();
        collect_headers(&include_dir, &mut headers);
        for header in &headers {
            println!("cargo:rerun-if-changed={}", header.display());
        }
    }

    link_feature(&manifest_dir);

    #[cfg(feature = "bindgen")]
    {
        run_bindgen(&manifest_dir);
    }
    #[cfg(not(feature = "bindgen"))]
    {
        let _ = &manifest_dir;
    }
}

/// Emit linker directives for the prebuilt library, if the `link` feature is on.
fn link_feature(manifest_dir: &Path) {
    if env::var_os("CARGO_FEATURE_LINK").is_none() {
        return;
    }

    let kind = requested_link_kind();
    let Some((dir, path)) = find_lib_dir(manifest_dir, &kind) else {
        println!(
            "cargo:warning=khostty-vt: no prebuilt libghostty-vt found (looked in \
             GHOSTTY_VT_LIB_DIR, {LIB_DIR_CANDIDATES:?} under {}). The crate will \
             typecheck but not link. Build it with `zig build -Dlibghostty-vt=true` \
             or set GHOSTTY_VT_LIB_DIR.",
            manifest_dir.display()
        );
        return;
    };

    println!("cargo:rustc-link-search=native={}", dir.display());
    println!("cargo:rustc-link-lib={}={}", kind, "ghostty-vt");

    // Integration tests and examples are separate executables, so they need an
    // rpath to resolve the shared library at run time.
    if kind != "static" {
        let dir = dir.display().to_string();
        if cfg!(target_os = "macos") {
            println!("cargo:rustc-link-arg=-Wl,-rpath,{dir}");
        } else if cfg!(target_os = "linux") {
            println!("cargo:rustc-link-arg=-Wl,-rpath,{dir}");
            println!("cargo:rustc-link-arg=-Wl,--enable-new-dtags");
        }
    }

    println!("cargo:rustc-cfg=ghostty_vt_linked");
    println!(
        "cargo:warning=khostty-vt: linking {} ({})",
        path.display(),
        kind
    );
}

/// Generate bindings into `$OUT_DIR/bindings.rs` for the drift check.
///
/// Only compiled when the `bindgen` feature is enabled, so a default build
/// never needs libclang or a C parsing dependency.
#[cfg(feature = "bindgen")]
fn run_bindgen(manifest_dir: &Path) {
    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let Some(include_dir) = find_include_dir(manifest_dir) else {
        println!(
            "cargo:warning=khostty-vt: bindgen feature enabled but no ghostty/vt.h found; \
             skipping binding generation"
        );
        return;
    };

    let header = include_dir.join("ghostty").join("vt.h");
    let bindings = bindgen::Builder::default()
        .header(header.display().to_string())
        .clang_arg(format!("-I{}", include_dir.display()))
        // Keep the output close to the hand-written module so the drift test
        // compares declarations rather than formatting choices.
        .layout_tests(false)
        .allowlist_function("ghostty_.*")
        .allowlist_type("Ghostty.*")
        .allowlist_var("GHOSTTY_.*")
        .generate_comments(false)
        .derive_default(false)
        .generate()
        .expect("bindgen failed to generate bindings for ghostty/vt.h");

    let target = out_dir.join("bindings.rs");
    bindings
        .write_to_file(&target)
        .expect("failed to write bindgen output");
    println!("cargo:rustc-cfg=ghostty_vt_bindgen");
    println!(
        "cargo:warning=khostty-vt: generated bindgen bindings at {}",
        target.display()
    );
}
