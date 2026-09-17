//! Drive a terminal the way an agent tool would: read the screen, find a failure,
//! snapshot the session, and turn a keypress into pty bytes.
//!
//! Run with:
//!
//! ```text
//! cargo run --example agent_session
//! ```

#[cfg(ghostty_vt_linked)]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use khostty_vt::key::{Key, KeyAction, KeyEncoder, KeyEvent, Mods};
    use khostty_vt::search::Search;
    use khostty_vt::snapshot::{encode, SnapshotDecoder};
    use khostty_vt::Terminal;

    let mut term = Terminal::new(56, 10)?;
    term.set_title("build")?;

    // The terminal answers the queries a program sends; an embedder routes those
    // bytes back to the pty.
    term.set_write_pty(Some(|bytes: &[u8]| {
        println!("  -> pty: {:?}", String::from_utf8_lossy(bytes));
    }));

    // A program runs and produces output.
    term.vt_write(b"\x1b[2J\x1b[H");
    term.vt_write(b"$ cargo test\r\n");
    term.vt_write(b"\x1b[32mtest result: ok\x1b[0m 41 passed\r\n");
    term.vt_write(b"some log output\r\nmore log output\r\n");
    term.vt_write(b"\x1b[31mtest result: FAILED\x1b[0m 1 failed\r\n");
    term.vt_write(b"$ ");

    println!("== screen ==");
    let text = screen_text(&term)?;
    for (index, line) in text.lines().enumerate() {
        println!("{index:>2} | {line}");
    }

    println!();
    println!("== search ==");
    let mut search = Search::new(&term)?;
    search.set_needle(&term, "FAILED")?;
    search.run(&term)?;
    println!("matches: {}", search.total_matches()?);
    if search.total_matches()? > 0 {
        search.select_next(&term)?;
        println!("selected text: {:?}", search.selected_text(&term)?);
        if let Some(matched) = search.selected_match()? {
            println!(
                "selected span: row {} col {}..{}",
                matched.start.y(),
                matched.start.x(),
                matched.end.x()
            );
        }
    }

    println!();
    println!("== snapshot ==");
    let bytes = encode(&term)?;
    println!("snapshot is {} bytes", bytes.len());
    let restored = SnapshotDecoder::from_bytes(&bytes)?.decode()?;
    println!("restored title: {:?}", restored.title()?);
    println!(
        "restored screen matches: {}",
        screen_text(&restored)? == text
    );

    println!();
    println!("== input ==");
    let encoder = KeyEncoder::new()?;
    let mut quit = KeyEvent::new()?;
    quit.set_action(KeyAction::Press);
    quit.set_key(Key::C);
    quit.set_mods(Mods::CTRL);
    quit.set_utf8("c");
    println!("Ctrl+C encodes to {:?}", encoder.encode(&quit)?);

    println!();
    println!("== program query ==");
    // Ask the terminal for its device attributes; the answer arrives on the
    // write_pty channel set up above.
    term.vt_write(b"\x1b[c");

    Ok(())
}

/// Extract the visible text of a terminal's active screen using only public API.
#[cfg(ghostty_vt_linked)]
fn screen_text(term: &khostty_vt::Terminal) -> Result<String, khostty_vt::GhosttyError> {
    use khostty_vt::render::RenderState;

    let mut state = RenderState::new()?;
    state.update(term)?;

    let mut lines: Vec<String> = Vec::new();
    let mut iter = state.rows()?;
    while iter.advance() {
        let mut row = String::new();
        {
            let cells = iter.bind_cells()?;
            while cells.advance() {
                if cells.grapheme_len()? == 0 {
                    continue;
                }
                row.push_str(&cells.graphemes_utf8()?);
            }
        }
        lines.push(row.trim_end().to_string());
    }
    while lines.last().is_some_and(|line| line.is_empty()) {
        lines.pop();
    }
    Ok(lines.join("\n"))
}

#[cfg(not(ghostty_vt_linked))]
fn main() {
    eprintln!(
        "khostty-vt was built without libghostty-vt, so this example cannot run.\n\
         Build it with `zig build -Dlibghostty-vt=true` in the Khostty checkout, or \
         point GHOSTTY_VT_LIB_DIR at a prebuilt library."
    );
}
