//! Parse VT bytes and print the resulting screen as plain text.
//!
//! Run with:
//!
//! ```text
//! cargo run --example screen_dump
//! ```
//!
//! This is the smallest useful thing to build on top of the crate: feed bytes in,
//! read the screen back out. The rendering loop below uses only the public API and
//! is the same shape as `tests/end_to_end.rs::screen_text`, so the example doubles
//! as documentation for what a real renderer has to do.

#[cfg(ghostty_vt_linked)]
fn main() -> Result<(), khostty_vt::GhosttyError> {
    use khostty_vt::render::RenderState;
    use khostty_vt::Terminal;

    let mut term = Terminal::new(48, 8)?;

    // A shell-ish transcript: a prompt, coloured build output, and a summary.
    term.vt_write(b"$ cargo build\r\n");
    term.vt_write(b"   \x1b[32mCompiling\x1b[0m khostty-vt v0.1.0\r\n");
    term.vt_write(b"   \x1b[32mFinished\x1b[0m dev profile in 1.2s\r\n");
    term.vt_write(b"\x1b[33mwarning\x1b[0m: unused variable `x`\r\n");
    term.vt_write(b"$ ");

    println!("== screen ==");
    println!("title: {:?}", term.title()?);
    println!("size:  {}x{}", term.cols()?, term.rows()?);
    println!("cursor: {:?}", term.cursor_position()?);
    println!();

    // Read the screen back through the render state.
    let mut state = RenderState::new()?;
    state.update(&term)?;
    let colors = state.colors()?;

    // The inner scope matters: the row iterator borrows the render state, so it
    // must go out of scope before the state can be cleaned. That is the borrow
    // checker enforcing the C header's rule that row data becomes invalid as soon
    // as the render state is mutated.
    {
        let mut iter = state.rows()?;
        let mut index = 0usize;
        while iter.advance() {
            let mut line = String::new();
            let mut coloured_cells = 0usize;

            // One reusable cell handle is bound per row, which is the pattern the
            // C API intends.
            let cells = iter.bind_cells()?;
            while cells.advance() {
                if cells.grapheme_len()? == 0 {
                    continue;
                }
                line.push_str(&cells.graphemes_utf8()?);
                if let Ok(Some(fg)) = cells.foreground() {
                    if fg != colors.foreground {
                        coloured_cells += 1;
                    }
                }
            }

            println!("{index:>2} |{line}|  ({coloured_cells} coloured cells)");
            index += 1;
        }
    }

    // Dirty state is how a renderer decides how much work a frame needs.
    println!();
    println!("dirty: {:?}", state.dirty()?);
    state.clean()?;
    println!("after clean: {:?}", state.dirty()?);

    Ok(())
}

#[cfg(not(ghostty_vt_linked))]
fn main() {
    eprintln!(
        "khostty-vt was built without libghostty-vt, so this example cannot run.\n\
         Build it with `zig build -Dlibghostty-vt=true` in the Khostty checkout, or \
         point GHOSTTY_VT_LIB_DIR at a prebuilt library."
    );
}
