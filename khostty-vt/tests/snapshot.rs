//! Integration tests for snapshot encode/decode against the real library.
//!
//! Gated on the `ghostty_vt_linked` cfg; see `tests/terminal.rs` for why.

#![cfg(ghostty_vt_linked)]

use khostty_vt::snapshot::{encode, encode_alloc, encode_to, SnapshotDecoder};
use khostty_vt::sys::Allocator;
use khostty_vt::terminal::{Screen, Viewport};
use khostty_vt::Terminal;

fn terminal() -> Terminal {
    Terminal::new(80, 24).expect("80x24 terminal")
}

#[test]
fn snapshot_is_non_empty_and_self_describing() {
    let mut term = terminal();
    term.vt_write(b"hello snapshot");
    let bytes = encode(&term).expect("encode");
    assert!(!bytes.is_empty());
    // The encoder writes a versioned magic; a snapshot that decoded to nothing
    // would mean the buffer protocol query/fill pair disagreed.
    assert!(bytes.len() > 16, "suspiciously small snapshot: {bytes:?}");
}

#[test]
fn alloc_and_vec_encoders_agree() {
    let mut term = terminal();
    term.vt_write(b"same bytes please");
    let vec_bytes = encode(&term).expect("buf encode");
    let owned = encode_alloc(&term, Allocator::default()).expect("alloc encode");
    assert_eq!(owned.as_slice(), vec_bytes.as_slice());
    assert_eq!(owned.len(), vec_bytes.len());
}

#[test]
fn streaming_encoder_matches_buffer_encoder() {
    let mut term = terminal();
    term.vt_write(b"stream me");
    let expected = encode(&term).expect("buf encode");

    let mut streamed: Vec<u8> = Vec::new();
    encode_to(&term, |chunk| {
        streamed.extend_from_slice(chunk);
        true
    })
    .expect("stream encode");

    assert_eq!(streamed, expected);
}

#[test]
fn streaming_encoder_reports_a_rejecting_sink() {
    let term = terminal();
    let err = encode_to(&term, |_chunk| false).expect_err("rejected sink");
    assert_eq!(err, khostty_vt::GhosttyError::IoError);
}

#[test]
fn one_shot_round_trip_restores_screen_state() {
    let mut source = terminal();
    source.vt_write(b"\x1b[2J\x1b[Hrestored line one\r\nline two\r\n\x1b[1;31mred");
    source.set_title("snapshot title").unwrap();

    let bytes = encode(&source).expect("encode");

    let decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let restored = decoder.decode().expect("decode");

    assert_eq!(restored.cols().unwrap(), source.cols().unwrap());
    assert_eq!(restored.rows().unwrap(), source.rows().unwrap());
    assert_eq!(
        restored.cursor_position().unwrap(),
        source.cursor_position().unwrap()
    );
    assert_eq!(restored.title().unwrap(), source.title().unwrap());
    assert_eq!(restored.active_screen().unwrap(), Screen::Primary);
    assert_eq!(
        restored.cursor_sgr_style().unwrap(),
        source.cursor_sgr_style().unwrap()
    );
}

#[test]
fn round_trip_preserves_scrollback() {
    let mut source = Terminal::new(20, 4).expect("20x4 terminal");
    for line in 1..=30 {
        source.vt_write(format!("row {line}\r\n").as_bytes());
    }
    let source_scrollback = source.scrollback_rows().unwrap();
    assert!(source_scrollback > 0, "test needs scrollback to exist");

    let bytes = encode(&source).expect("encode");
    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");

    assert_eq!(restored.scrollback_rows().unwrap(), source_scrollback);
    assert_eq!(restored.total_rows().unwrap(), source.total_rows().unwrap());
}

#[test]
fn incremental_ready_then_next_reaches_the_same_state() {
    let mut source = Terminal::new(20, 4).expect("20x4 terminal");
    for line in 1..=40 {
        source.vt_write(format!("history line {line}\r\n").as_bytes());
    }
    let bytes = encode(&source).expect("encode");

    let mut decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let mut ready = decoder.ready().expect("ready");

    // The terminal is usable immediately after READY, before history lands.
    assert_eq!(ready.terminal().cols().unwrap(), 20);
    assert_eq!(ready.terminal().rows().unwrap(), 4);
    assert!(ready.progress().expect("progress").source_offset > 0);

    ready.finish().expect("drain history");
    assert_eq!(
        ready.terminal().scrollback_rows().unwrap(),
        source.scrollback_rows().unwrap(),
        "history replay must recover the same scrollback depth"
    );

    // Live input is accepted after replay too, and adds to the restored state
    // rather than replacing it.
    let before = ready.terminal().total_rows().unwrap();
    ready
        .terminal_mut()
        .vt_write(b"live input after replay\r\n");
    assert!(ready.terminal().total_rows().unwrap() >= before);
}

#[test]
fn next_page_reports_finish_with_false() {
    let mut source = terminal();
    source.vt_write(b"short");
    let bytes = encode(&source).expect("encode");

    let mut decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let mut ready = decoder.ready().expect("ready");

    // Drain to FINISH, counting pages. A snapshot with no history should report
    // FINISH on the first call.
    let mut pages = 0usize;
    while ready.next_page().expect("next") {
        pages += 1;
        assert!(pages < 100_000, "history replay did not terminate");
    }
    // Calling again after FINISH must also report false rather than erroring.
    assert!(!ready.next_page().expect("next after finish"));
}

#[test]
fn finish_owned_returns_the_terminal() {
    let mut source = terminal();
    source.vt_write(b"owned");
    let bytes = encode(&source).expect("encode");

    let mut decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let ready = decoder.ready().expect("ready");
    let restored = ready.finish_owned().expect("finish");

    assert_eq!(restored.cols().unwrap(), 80);
    assert_eq!(restored.cursor_position().unwrap(), (5, 0));
}

#[test]
fn owning_decoder_accepts_a_vec() {
    let mut source = terminal();
    source.vt_write(b"vec-owned");
    let bytes = encode(&source).expect("encode");

    let decoder = SnapshotDecoder::from_vec(bytes).expect("decoder");
    let restored = decoder.decode().expect("decode");
    assert_eq!(restored.cursor_position().unwrap(), (9, 0));
}

#[test]
fn decoder_options_are_settable_before_decoding() {
    let mut source = terminal();
    source.vt_write(b"options");
    let bytes = encode(&source).expect("encode");

    let mut decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    decoder.set_max_continuation_bytes(4096).expect("set max");
    decoder.set_retain_continuation(true).expect("set retain");
    assert_eq!(decoder.max_continuation_bytes().unwrap(), 4096);

    let restored = decoder.decode().expect("decode");
    assert_eq!(restored.cursor_position().unwrap(), (7, 0));
}

#[test]
fn decoder_options_are_rejected_after_decoding_starts() {
    let mut source = terminal();
    source.vt_write(b"poisoned");
    let bytes = encode(&source).expect("encode");

    let mut decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let _ready = decoder.ready().expect("ready");
    // The option lifecycle contract says options are only settable before
    // decoding starts.
    assert_eq!(
        decoder.set_max_continuation_bytes(1),
        Err(khostty_vt::GhosttyError::InvalidValue)
    );
}

#[test]
fn alternate_screen_survives_a_round_trip() {
    let mut source = terminal();
    source.vt_write(b"\x1b[?1049h");
    source.vt_write(b"alt screen content");
    assert_eq!(source.active_screen().unwrap(), Screen::Alternate);

    let bytes = encode(&source).expect("encode");
    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");
    assert_eq!(restored.active_screen().unwrap(), Screen::Alternate);
    assert_eq!(restored.cursor_position().unwrap(), (18, 0));
}

#[test]
fn restored_terminal_keeps_accumulating_output() {
    let mut source = terminal();
    source.vt_write(b"before");
    let bytes = encode(&source).expect("encode");

    let mut restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");
    restored.vt_write(b" after");
    assert_eq!(restored.cursor_position().unwrap(), (12, 0));
    assert!(restored.vt_ground().unwrap());
}

#[test]
fn round_trip_of_a_scrolled_viewport_preserves_geometry() {
    let mut source = Terminal::new(30, 5).expect("30x5 terminal");
    for line in 0..50 {
        source.vt_write(format!("{line:03} --------------------\r\n").as_bytes());
    }
    source.scroll_viewport(Viewport::Top);
    let source_scrollbar = source.scrollbar().unwrap();

    let bytes = encode(&source).expect("encode");
    let restored = SnapshotDecoder::from_bytes(&bytes)
        .expect("decoder")
        .decode()
        .expect("decode");
    let restored_scrollbar = restored.scrollbar().unwrap();
    assert_eq!(restored_scrollbar.total, source_scrollbar.total);
    assert_eq!(restored_scrollbar.len, source_scrollbar.len);
}

#[test]
fn truncated_input_is_rejected_rather_than_silently_accepted() {
    let mut source = terminal();
    source.vt_write(b"complete snapshot");
    let bytes = encode(&source).expect("encode");

    // Cut the FINISH marker and the trailing bytes off.
    let truncated = &bytes[..bytes.len() / 2];
    let decoder = SnapshotDecoder::from_bytes(truncated).expect("decoder");
    assert!(
        decoder.decode().is_err(),
        "a truncated snapshot must not decode successfully"
    );
}

#[test]
fn trailing_bytes_after_finish_are_reported_by_source_offset() {
    let mut source = terminal();
    source.vt_write(b"payload");
    let mut bytes = encode(&source).expect("encode");
    let snapshot_len = bytes.len();
    bytes.extend_from_slice(b"TRAILING-EXTRA-BYTES");

    // Decoding must stop at FINISH and ignore the trailing bytes entirely.
    let decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let restored = decoder.decode().expect("decode");
    assert_eq!(restored.cursor_position().unwrap(), (7, 0));

    // Re-run incrementally to observe SOURCE_OFFSET. The decoder must never
    // report having consumed past the FINISH marker, i.e. it must not have read
    // the trailing bytes.
    let mut decoder = SnapshotDecoder::from_bytes(&bytes).expect("decoder");
    let mut ready = decoder.ready().expect("ready");
    let mut furthest = ready.progress().expect("progress").source_offset;
    loop {
        let page = ready.progress().expect("progress").source_offset;
        furthest = furthest.max(page);
        if !ready.next_page().expect("next") {
            break;
        }
    }
    assert!(furthest > 0, "the decoder consumed no input");
    assert!(
        furthest <= snapshot_len,
        "decoder reported consuming {furthest} bytes, past the {snapshot_len}-byte snapshot"
    );
    assert!(
        furthest < bytes.len(),
        "decoder consumed the trailing bytes past FINISH"
    );
}
