//! Guards the raw bindings against drift from the C headers.
//!
//! `src/ffi.rs` is generated from `include/ghostty/vt.h` and
//! `include/ghostty/vt/**` by `tools/gen_ffi.py`. A generated file that is never
//! re-checked against its source is just a hand-written file with extra steps, so
//! this test re-derives the function set from the headers *at test time* and
//! compares it against what the binding actually declares.
//!
//! It deliberately duplicates the generator's two non-obvious rules, because
//! those rules are where drift would hide:
//!
//! 1. Only lines carrying `GHOSTTY_API` are exported functions. The macro's own
//!    `#define` in `types.h` must not be mistaken for a declaration, and
//!    `static inline` helpers in `modes.h` are not exported symbols at all.
//! 2. Declarations inside `#ifdef __wasm__` exist only on WebAssembly and are
//!    intentionally excluded, matching what libclang sees on a native target.
//!
//! This test needs no C toolchain and no Python, so it runs everywhere.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

/// Path to the Khostty checkout's C headers, relative to this crate.
fn include_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("crate lives inside the Khostty checkout")
        .join("include")
}

/// Recursively collect every `.h` file under `dir`.
fn header_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir(dir) else {
        return out;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            out.extend(header_files(&path));
        } else if path.extension().is_some_and(|ext| ext == "h") {
            out.push(path);
        }
    }
    out.sort();
    out
}

/// Remove `/* ... */` and `// ...` comments, preserving line structure.
fn strip_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    let bytes = src.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'/' && index + 1 < bytes.len() && bytes[index + 1] == b'*' {
            let mut cursor = index + 2;
            while cursor + 1 < bytes.len() && !(bytes[cursor] == b'*' && bytes[cursor + 1] == b'/')
            {
                if bytes[cursor] == b'\n' {
                    out.push('\n');
                }
                cursor += 1;
            }
            index = cursor + 2;
            continue;
        }
        if bytes[index] == b'/' && index + 1 < bytes.len() && bytes[index + 1] == b'/' {
            let mut cursor = index;
            while cursor < bytes.len() && bytes[cursor] != b'\n' {
                cursor += 1;
            }
            index = cursor;
            continue;
        }
        out.push(bytes[index] as char);
        index += 1;
    }
    out
}

/// Names of `#ifdef __wasm__`-only declarations, so they can be excluded.
fn wasm_only_names(src: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let mut depth = 0usize;
    for line in src.lines() {
        let trimmed = line.trim();
        if depth == 0 {
            if trimmed.starts_with("#ifdef __wasm__") || trimmed.starts_with("#ifndef __wasm__") {
                depth = 1;
                continue;
            }
            continue;
        }
        if trimmed.starts_with("#if") {
            depth += 1;
        } else if trimmed.starts_with("#endif") {
            depth -= 1;
            if depth == 0 {
                continue;
            }
        }
        for name in exported_names_in(line) {
            out.insert(name);
        }
    }
    out
}

/// `ghostty_*` function names declared on one line, if it carries `GHOSTTY_API`.
fn exported_names_in(line: &str) -> Vec<String> {
    if !line.contains("GHOSTTY_API") {
        return Vec::new();
    }
    // The `#define GHOSTTY_API ...` in types.h is not a declaration.
    if line.trim_start().starts_with('#') {
        return Vec::new();
    }
    // A declaration may span lines, so a name can sit on a continuation line
    // without `GHOSTTY_API` on that same line; the caller handles that by
    // scanning joined declarations instead. Here we only need the
    // `GHOSTTY_API <ret> name(` shape on one line.
    let mut names = Vec::new();
    if let Some(api) = line.find("GHOSTTY_API") {
        let rest = &line[api + "GHOSTTY_API".len()..];
        if let Some(paren) = rest.find('(') {
            let head = &rest[..paren];
            if let Some(name) = head.split_whitespace().last() {
                if name.starts_with("ghostty_") {
                    names.push(name.to_string());
                }
            }
        }
    }
    names
}

/// Declarations across a whole file, joined so multi-line signatures are handled.
fn declared_names(src: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    // Any `ghostty_foo(` that is immediately preceded by a `GHOSTTY_API`
    // somewhere earlier in the same declaration is a declaration. Collapsing
    // whitespace first makes multi-line signatures a single line.
    let flattened = src.replace('\n', " ");
    let mut rest = flattened.as_str();
    while let Some(api) = rest.find("GHOSTTY_API") {
        let after = &rest[api + "GHOSTTY_API".len()..];
        // A declaration ends at the first ';' after the macro.
        let end = after.find(';').unwrap_or(after.len());
        let declaration = &after[..end];
        if let Some(paren) = declaration.find('(') {
            let head = &declaration[..paren];
            if let Some(name) = head.split_whitespace().last() {
                let name = name.trim_start_matches('*');
                if name.starts_with("ghostty_") {
                    out.insert(name.to_string());
                }
            }
        }
        rest = &after[end.min(after.len())..];
    }
    out
}

/// Every exported function the headers declare on a native target.
///
/// Scope is exactly `include/ghostty/vt.h` plus everything under
/// `include/ghostty/vt/`, matching the generator. `include/ghostty.h` is the
/// *application* API (window and surface management) rather than the terminal
/// library, so `ghostty_surface_*` and friends are deliberately out of scope
/// here.
fn header_functions() -> BTreeSet<String> {
    let dir = include_dir();
    let umbrella = dir.join("ghostty").join("vt.h");
    let vt_dir = dir.join("ghostty").join("vt");
    assert!(
        umbrella.is_file(),
        "cannot find include/ghostty/vt.h relative to the crate; \
         this test must run from inside the Khostty checkout"
    );

    let mut paths = vec![umbrella];
    paths.extend(header_files(&vt_dir));

    let mut all = BTreeSet::new();
    let mut wasm_only = BTreeSet::new();
    for path in paths {
        let raw = fs::read_to_string(&path).expect("header is readable UTF-8");
        let stripped = strip_comments(&raw);
        wasm_only.extend(wasm_only_names(&stripped));
        all.extend(declared_names(&stripped));
    }
    all.difference(&wasm_only).cloned().collect()
}

/// Every function `src/ffi.rs` declares in its `extern "C"` block.
fn binding_functions() -> BTreeSet<String> {
    let src = fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("src/ffi.rs"))
        .expect("src/ffi.rs is readable");
    let mut out = BTreeSet::new();
    for line in src.lines() {
        let trimmed = line.trim();
        let Some(rest) = trimmed.strip_prefix("pub fn ") else {
            continue;
        };
        let Some(paren) = rest.find('(') else {
            continue;
        };
        let name = &rest[..paren];
        if name.starts_with("ghostty_") {
            out.insert(name.to_string());
        }
    }
    out
}

#[test]
fn the_headers_declare_the_functions_we_expect_to_find() {
    // A sanity check on the extraction itself: if the parser silently found
    // nothing, the coverage tests below would pass vacuously.
    let functions = header_functions();
    assert!(
        functions.len() > 150,
        "expected well over 150 exported functions in the headers, found {}",
        functions.len()
    );
    assert!(
        functions.contains("ghostty_terminal_new"),
        "the extraction must find ghostty_terminal_new"
    );
    assert!(
        !functions.contains("ghostty_mode_new"),
        "static inline helpers in modes.h are not exported symbols"
    );
    assert!(
        !functions.contains("ghostty_wasm_alloc"),
        "wasm-only declarations must be excluded on a native target"
    );
    assert!(
        !functions.contains("_WIN32"),
        "the GHOSTTY_API macro definition must not be read as a declaration"
    );
    assert!(
        !functions
            .iter()
            .any(|name| name.starts_with("ghostty_surface_")),
        "include/ghostty.h is the application API, not the terminal library, \
         and is deliberately outside this binding's scope"
    );
}

#[test]
fn every_header_function_is_bound() {
    let headers = header_functions();
    let bound = binding_functions();

    let missing: Vec<&String> = headers.difference(&bound).collect();
    assert!(
        missing.is_empty(),
        "src/ffi.rs is missing {} exported function(s): {:#?}\n\
         Regenerate with `python3 tools/gen_ffi.py`.",
        missing.len(),
        missing
    );
}

#[test]
fn the_binding_declares_nothing_the_headers_do_not() {
    let headers = header_functions();
    let bound = binding_functions();

    let extra: Vec<&String> = bound.difference(&headers).collect();
    assert!(
        extra.is_empty(),
        "src/ffi.rs declares {} function(s) absent from the headers: {:#?}\n\
         A binding for a symbol the library does not export would fail to link \
         when called.",
        extra.len(),
        extra
    );
}

#[test]
fn the_recorded_function_count_matches_reality() {
    let bound = binding_functions();
    assert_eq!(
        khostty_vt::ffi::BINDING_FUNCTION_COUNT,
        bound.len(),
        "BINDING_FUNCTION_COUNT is out of step with the declared bindings"
    );
}

#[test]
fn no_binding_carries_the_wasm_only_symbols() {
    let bound = binding_functions();
    let wasm: Vec<&String> = bound
        .iter()
        .filter(|name| name.starts_with("ghostty_wasm_"))
        .collect();
    assert!(
        wasm.is_empty(),
        "wasm-only functions cannot be linked on this target: {wasm:#?}"
    );
}
