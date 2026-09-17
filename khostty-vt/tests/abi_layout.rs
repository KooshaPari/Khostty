//! Proves that Rust and the C compiler agree on the layout of every
//! libghostty-vt type this crate marshals.
//!
//! The safe wrappers pass pointers across the FFI boundary and depend on both
//! sides agreeing on size and alignment. A disagreement is a memory-safety bug,
//! not a cosmetic one. A concrete example caught during development:
//! `GHOSTTY_TERMINAL_DATA_CURSOR_STYLE` is documented as returning a whole
//! `GhosttyStyle` (72 bytes), and marshalling it into a 4-byte slot corrupted
//! the stack. This test now makes that class of mistake impossible to ship.
//!
//! The C-side numbers come from `tests/abi_layout.txt`, produced by compiling and
//! running a probe against the real headers (`tools/dump_abi_layout.py`). The
//! file records when it was observed and which compiler produced it, so the
//! evidence is dated rather than implied.

use std::collections::BTreeMap;
use std::mem::{align_of, size_of};

use khostty_vt::ffi;

/// Snapshot of the C compiler's measurements, embedded at compile time so the
/// test does not depend on the working directory.
const ABI_SNAPSHOT: &str = include_str!("abi_layout.txt");

/// `(name, size, align)` for every mirrored type.
const MIRRORED: &[(&str, usize, usize)] = &[
    (
        "GhosttyAllocator",
        size_of::<ffi::GhosttyAllocator>(),
        align_of::<ffi::GhosttyAllocator>(),
    ),
    (
        "GhosttyAllocatorVtable",
        size_of::<ffi::GhosttyAllocatorVtable>(),
        align_of::<ffi::GhosttyAllocatorVtable>(),
    ),
    (
        "GhosttyBuffer",
        size_of::<ffi::GhosttyBuffer>(),
        align_of::<ffi::GhosttyBuffer>(),
    ),
    (
        "GhosttyCell",
        size_of::<ffi::GhosttyCell>(),
        align_of::<ffi::GhosttyCell>(),
    ),
    (
        "GhosttyCodepoints",
        size_of::<ffi::GhosttyCodepoints>(),
        align_of::<ffi::GhosttyCodepoints>(),
    ),
    (
        "GhosttyColorPaletteIndex",
        size_of::<ffi::GhosttyColorPaletteIndex>(),
        align_of::<ffi::GhosttyColorPaletteIndex>(),
    ),
    (
        "GhosttyColorPaletteMask",
        size_of::<ffi::GhosttyColorPaletteMask>(),
        align_of::<ffi::GhosttyColorPaletteMask>(),
    ),
    (
        "GhosttyColorRgb",
        size_of::<ffi::GhosttyColorRgb>(),
        align_of::<ffi::GhosttyColorRgb>(),
    ),
    (
        "GhosttyGridRef",
        size_of::<ffi::GhosttyGridRef>(),
        align_of::<ffi::GhosttyGridRef>(),
    ),
    (
        "GhosttyMode",
        size_of::<ffi::GhosttyMode>(),
        align_of::<ffi::GhosttyMode>(),
    ),
    (
        "GhosttyMods",
        size_of::<ffi::GhosttyMods>(),
        align_of::<ffi::GhosttyMods>(),
    ),
    (
        "GhosttyMouseEncoderSize",
        size_of::<ffi::GhosttyMouseEncoderSize>(),
        align_of::<ffi::GhosttyMouseEncoderSize>(),
    ),
    (
        "GhosttyMousePosition",
        size_of::<ffi::GhosttyMousePosition>(),
        align_of::<ffi::GhosttyMousePosition>(),
    ),
    (
        "GhosttyPoint",
        size_of::<ffi::GhosttyPoint>(),
        align_of::<ffi::GhosttyPoint>(),
    ),
    (
        "GhosttyPointCoordinate",
        size_of::<ffi::GhosttyPointCoordinate>(),
        align_of::<ffi::GhosttyPointCoordinate>(),
    ),
    (
        "GhosttyPointValue",
        size_of::<ffi::GhosttyPointValue>(),
        align_of::<ffi::GhosttyPointValue>(),
    ),
    (
        "GhosttyReader",
        size_of::<ffi::GhosttyReader>(),
        align_of::<ffi::GhosttyReader>(),
    ),
    (
        "GhosttyRenderStateColors",
        size_of::<ffi::GhosttyRenderStateColors>(),
        align_of::<ffi::GhosttyRenderStateColors>(),
    ),
    (
        "GhosttyRenderStateCursor",
        size_of::<ffi::GhosttyRenderStateCursor>(),
        align_of::<ffi::GhosttyRenderStateCursor>(),
    ),
    (
        "GhosttyRenderStateRowSelection",
        size_of::<ffi::GhosttyRenderStateRowSelection>(),
        align_of::<ffi::GhosttyRenderStateRowSelection>(),
    ),
    (
        "GhosttyRow",
        size_of::<ffi::GhosttyRow>(),
        align_of::<ffi::GhosttyRow>(),
    ),
    (
        "GhosttySelection",
        size_of::<ffi::GhosttySelection>(),
        align_of::<ffi::GhosttySelection>(),
    ),
    (
        "GhosttySelectionBuffer",
        size_of::<ffi::GhosttySelectionBuffer>(),
        align_of::<ffi::GhosttySelectionBuffer>(),
    ),
    (
        "GhosttySizeReportSize",
        size_of::<ffi::GhosttySizeReportSize>(),
        align_of::<ffi::GhosttySizeReportSize>(),
    ),
    (
        "GhosttySizeReportStyle",
        size_of::<ffi::GhosttySizeReportStyle>(),
        align_of::<ffi::GhosttySizeReportStyle>(),
    ),
    (
        "GhosttyString",
        size_of::<ffi::GhosttyString>(),
        align_of::<ffi::GhosttyString>(),
    ),
    (
        "GhosttyStyle",
        size_of::<ffi::GhosttyStyle>(),
        align_of::<ffi::GhosttyStyle>(),
    ),
    (
        "GhosttyStyleColor",
        size_of::<ffi::GhosttyStyleColor>(),
        align_of::<ffi::GhosttyStyleColor>(),
    ),
    (
        "GhosttyStyleColorValue",
        size_of::<ffi::GhosttyStyleColorValue>(),
        align_of::<ffi::GhosttyStyleColorValue>(),
    ),
    (
        "GhosttyStyleId",
        size_of::<ffi::GhosttyStyleId>(),
        align_of::<ffi::GhosttyStyleId>(),
    ),
    (
        "GhosttySurfacePosition",
        size_of::<ffi::GhosttySurfacePosition>(),
        align_of::<ffi::GhosttySurfacePosition>(),
    ),
    (
        "GhosttyTerminalModeConfig",
        size_of::<ffi::GhosttyTerminalModeConfig>(),
        align_of::<ffi::GhosttyTerminalModeConfig>(),
    ),
    (
        "GhosttyTerminalProgressReport",
        size_of::<ffi::GhosttyTerminalProgressReport>(),
        align_of::<ffi::GhosttyTerminalProgressReport>(),
    ),
    (
        "GhosttyTerminalScrollViewport",
        size_of::<ffi::GhosttyTerminalScrollViewport>(),
        align_of::<ffi::GhosttyTerminalScrollViewport>(),
    ),
    (
        "GhosttyTerminalScrollViewportValue",
        size_of::<ffi::GhosttyTerminalScrollViewportValue>(),
        align_of::<ffi::GhosttyTerminalScrollViewportValue>(),
    ),
    (
        "GhosttyTerminalScrollbar",
        size_of::<ffi::GhosttyTerminalScrollbar>(),
        align_of::<ffi::GhosttyTerminalScrollbar>(),
    ),
    (
        "GhosttyWriter",
        size_of::<ffi::GhosttyWriter>(),
        align_of::<ffi::GhosttyWriter>(),
    ),
];

/// Parse `tests/abi_layout.txt` into name -> (size, align).
fn c_layout() -> BTreeMap<String, (usize, usize)> {
    let mut out = BTreeMap::new();
    for line in ABI_SNAPSHOT.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (name, rest) = line.split_once(' ').expect("`Name size=.. align=..`");
        let mut size = None;
        let mut align = None;
        for field in rest.split_whitespace() {
            let (key, value) = field.split_once('=').expect("key=value");
            let value: usize = value.parse().expect("numeric size/align");
            match key {
                "size" => size = Some(value),
                "align" => align = Some(value),
                other => panic!("unexpected field {other} in {line:?}"),
            }
        }
        out.insert(name.to_string(), (size.unwrap(), align.unwrap()));
    }
    out
}

#[test]
fn snapshot_records_when_and_how_it_was_observed() {
    // The cockpit presentation contract requires evidence to carry its
    // observation date and provenance rather than silently becoming a fresh
    // pass.
    assert!(
        ABI_SNAPSHOT.contains("# observed: "),
        "the ABI snapshot must record its observation timestamp"
    );
    assert!(
        ABI_SNAPSHOT.contains("# compiler: "),
        "the ABI snapshot must record which compiler produced it"
    );
    assert!(
        ABI_SNAPSHOT.contains("# headers:"),
        "the ABI snapshot must record which headers it was taken against"
    );
}

#[test]
fn every_mirrored_type_matches_the_c_compiler() {
    let c = c_layout();
    let mut mismatches = Vec::new();

    for (name, rust_size, rust_align) in MIRRORED {
        let Some(&(c_size, c_align)) = c.get(*name) else {
            mismatches.push(format!("{name}: missing from tests/abi_layout.txt"));
            continue;
        };
        if (c_size, c_align) != (*rust_size, *rust_align) {
            mismatches.push(format!(
                "{name}: C says size={c_size} align={c_align}, \
                 Rust says size={rust_size} align={rust_align}"
            ));
        }
    }

    assert!(
        mismatches.is_empty(),
        "ABI layout disagreements between Rust and C:\n  {}",
        mismatches.join("\n  ")
    );
}

#[test]
fn the_snapshot_covers_exactly_the_mirrored_set() {
    let c = c_layout();
    let expected: std::collections::BTreeSet<&str> = MIRRORED.iter().map(|(n, _, _)| *n).collect();
    let recorded: std::collections::BTreeSet<&str> = c.keys().map(String::as_str).collect();
    assert_eq!(
        expected, recorded,
        "tests/abi_layout.txt and the MIRRORED table have drifted apart"
    );
}

#[test]
fn ghostty_style_is_the_large_struct_that_broke_the_naive_binding() {
    // Regression guard. Before this crate learned that
    // GHOSTTY_TERMINAL_DATA_CURSOR_STYLE returns a whole `GhosttyStyle`, the
    // accessor read it into a 4-byte slot and corrupted the stack.
    let c = c_layout();
    let (style_size, _) = c["GhosttyStyle"];
    assert!(
        style_size > size_of::<i32>(),
        "GhosttyStyle must be bigger than a scalar; the naive marshalling bug is back"
    );
    assert_eq!(style_size, size_of::<ffi::GhosttyStyle>());
}
