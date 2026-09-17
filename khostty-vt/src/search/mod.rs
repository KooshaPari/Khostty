//! Searching a terminal's contents, including scrollback.
//!
//! [`Search`] mirrors `GhosttySearch`. A search is created against a terminal
//! and looks for a needle; results stay in sync with the live screens, survive
//! primary/alternate screen switches, and recover from resize, reflow, reset,
//! and scrollback pruning. Matching is byte-exact except for ASCII letters,
//! which compare case-insensitively.
//!
//! # Why the terminal is a parameter
//!
//! The C API stores the terminal inside the search at construction time, and
//! three entry points carry an exclusivity requirement stated in the header:
//!
//! * `ghostty_search_feed` "requires exclusive terminal access",
//! * replacing or clearing the needle "releases tracked state held within the
//!   terminal, so the caller must serialize this with all other access", and
//! * the select options "read the terminal, so the caller must serialize it".
//!
//! If [`Search`] simply held a `&Terminal`, none of those calls could be made
//! after a terminal write, because writing needs `&mut Terminal` and the search
//! would still hold the shared borrow. So the terminal is passed to each
//! terminal-touching method instead:
//!
//! * holding a `&Terminal` for the duration of the call is exactly the
//!   exclusivity the header asks for, since `Terminal` is not `Sync` and writes
//!   need `&mut`;
//! * the handle is checked against the one the search was created with, so a
//!   mismatched terminal is rejected rather than silently searched.
//!
//! [`Search::tick`] never touches the terminal, so it takes no argument, matching
//! the header's note that ticking "can be safely called from a thread".
//!
//! # Match lifetime
//!
//! Matches are [`Selection`] snapshots. Upstream's rule: they are valid only
//! until the next operation that modifies the terminal. Read them after a feed,
//! use them before the terminal changes again, and re-read rather than cache.
//! The selected match is kept accurate internally across terminal changes, so
//! following a match means re-reading [`Search::selected_match`] after each feed.

pub mod types;

pub use types::{SearchScroll, SearchStatus};

use crate::error::{GhosttyError, Result};
use crate::ffi;
use crate::selection::Selection;
use crate::sys::Allocator;
use crate::terminal::Terminal;
use core::marker::PhantomData;
use core::ptr;

/// A search over one terminal.
///
/// Dropping this value calls `ghostty_search_free`. The search and its terminal
/// may be freed in either order: the C implementation tracks terminal lifetime
/// and fails cleanly instead of dereferencing a freed terminal. The
/// terminal-checked methods below make that situation unreachable anyway, since
/// every terminal-touching call must be given a live `&Terminal`.
pub struct Search {
    raw: ffi::GhosttySearch,
    /// Handle the search was created with, kept for identity checks only. Never
    /// dereferenced.
    terminal: ffi::GhosttyTerminal,
    _not_thread_safe: PhantomData<*mut ()>,
}

impl Search {
    /// Create a search over `terminal`.
    ///
    /// The search borrows the terminal; it never frees it, and any number of
    /// searches may share one terminal alongside other readers such as
    /// formatters and render states.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_new` reports.
    pub fn new(terminal: &Terminal) -> Result<Self> {
        Self::with_allocator(terminal, Allocator::default())
    }

    /// Create a search over `terminal` using a specific allocator.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_new` reports.
    pub fn with_allocator(terminal: &Terminal, allocator: Allocator) -> Result<Self> {
        let mut raw: ffi::GhosttySearch = ptr::null_mut();
        // SAFETY: `allocator.as_ptr()` is NULL or a live allocator;
        // `&mut raw` is a valid out-parameter; `terminal.as_raw()` is live and
        // outlives this call, and the search borrows rather than takes it.
        let code =
            unsafe { ffi::ghostty_search_new(allocator.as_ptr(), &mut raw, terminal.as_raw()) };
        GhosttyError::from_result(code)?;
        if raw.is_null() {
            return Err(GhosttyError::NullHandle);
        }
        Ok(Search {
            raw,
            terminal: terminal.as_raw(),
            _not_thread_safe: PhantomData,
        })
    }

    /// Set the needle, starting or restarting the search.
    ///
    /// An empty needle clears the search and returns it to idle. Upstream states
    /// that replacing or clearing a needle releases tracked state held inside the
    /// terminal, which is why the terminal is taken here: holding `&Terminal` is
    /// what serializes this against the terminal's own mutators.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] if `terminal` is not the terminal this
    /// search was created with, plus whatever `ghostty_search_set` reports.
    pub fn set_needle(&mut self, terminal: &Terminal, needle: &str) -> Result<()> {
        self.check_terminal(terminal)?;
        if needle.is_empty() {
            return self.clear_needle(terminal);
        }
        let value = ffi::GhosttyString {
            ptr: needle.as_ptr(),
            len: needle.len(),
        };
        self.set_opt(
            ffi::GHOSTTY_SEARCH_OPT_NEEDLE,
            (&value as *const ffi::GhosttyString).cast(),
        )
    }

    /// Clear the needle, returning the search to idle.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] for a mismatched terminal, plus whatever
    /// `ghostty_search_set` reports.
    pub fn clear_needle(&mut self, terminal: &Terminal) -> Result<()> {
        self.check_terminal(terminal)?;
        // A NULL value is the documented "clear" spelling.
        self.set_opt(ffi::GHOSTTY_SEARCH_OPT_NEEDLE, ptr::null())
    }

    /// Select the next match, moving toward older content and wrapping around
    /// past the oldest.
    ///
    /// Catches up with the terminal first, so it is safe to call at any time
    /// relative to feeds. The viewport scrolls according to
    /// [`Search::set_scroll_policy`].
    ///
    /// # Errors
    ///
    /// [`GhosttyError::NoValue`] when there are no matches,
    /// [`GhosttyError::InvalidValue`] for a mismatched terminal, plus whatever
    /// `ghostty_search_set` reports.
    pub fn select_next(&mut self, terminal: &Terminal) -> Result<()> {
        self.check_terminal(terminal)?;
        self.set_opt(ffi::GHOSTTY_SEARCH_OPT_SELECT_NEXT, ptr::null())
    }

    /// Select the previous match, moving toward newer content and wrapping
    /// around past the newest.
    ///
    /// # Errors
    ///
    /// As [`Search::select_next`].
    pub fn select_prev(&mut self, terminal: &Terminal) -> Result<()> {
        self.check_terminal(terminal)?;
        self.set_opt(ffi::GHOSTTY_SEARCH_OPT_SELECT_PREV, ptr::null())
    }

    /// Set the scroll policy applied by the select options.
    ///
    /// This only modifies search-owned state and never reads the terminal, so no
    /// terminal is needed. The policy persists until changed.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_set` reports.
    pub fn set_scroll_policy(&mut self, policy: SearchScroll) -> Result<()> {
        let value = policy.to_raw();
        self.set_opt(
            ffi::GHOSTTY_SEARCH_OPT_SELECT_SCROLL,
            (&value as *const ffi::GhosttySearchScroll).cast(),
        )
    }

    /// The current scroll policy.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_get` reports.
    pub fn scroll_policy(&self) -> Result<SearchScroll> {
        let mut raw: ffi::GhosttySearchScroll = ffi::GHOSTTY_SEARCH_SCROLL_IF_NEEDED;
        self.get_into(ffi::GHOSTTY_SEARCH_DATA_SELECT_SCROLL, &mut raw)?;
        Ok(SearchScroll::from_raw(raw))
    }

    /// Make a bounded amount of progress on data the search has already copied.
    ///
    /// This never touches the terminal, which is why it takes no terminal
    /// argument and why upstream documents it as safe to call from a thread.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_tick` reports.
    pub fn tick(&mut self) -> Result<SearchStatus> {
        let mut status: ffi::GhosttySearchStatus = ffi::GHOSTTY_SEARCH_STATUS_RUNNING;
        // SAFETY: `self.raw` is live and `&mut status` is a valid out-parameter.
        let code = unsafe { ffi::ghostty_search_tick(self.raw, &mut status) };
        GhosttyError::from_result(code)?;
        Ok(SearchStatus::from_raw(status))
    }

    /// Copy more terminal data into the search and pick up terminal changes.
    ///
    /// Feeding is the only way the search learns that the terminal changed, so
    /// keep feeding periodically while the search is in use. Reads the terminal,
    /// hence the `&Terminal` argument and its exclusivity guarantee.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] for a mismatched terminal, plus whatever
    /// `ghostty_search_feed` reports.
    pub fn feed(&mut self, terminal: &Terminal) -> Result<()> {
        self.check_terminal(terminal)?;
        // SAFETY: `self.raw` is live; the live `&Terminal` argument is what
        // serializes this against other terminal access.
        let code = unsafe { ffi::ghostty_search_feed(self.raw) };
        GhosttyError::from_result(code)
    }

    /// Blocking convenience: feed and tick until the search is caught up.
    ///
    /// Suitable for agent tooling and one-shot queries; interactive embedders
    /// should interleave [`Search::tick`] and [`Search::feed`] with their event
    /// loop instead, so a large scrollback search never stalls a frame.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] for a mismatched terminal, plus whatever
    /// `ghostty_search_run` reports.
    pub fn run(&mut self, terminal: &Terminal) -> Result<()> {
        self.check_terminal(terminal)?;
        // SAFETY: `self.raw` is live and the terminal is alive and exclusively
        // borrowed for the duration of the call.
        let code = unsafe { ffi::ghostty_search_run(self.raw) };
        GhosttyError::from_result(code)
    }

    /// The needle this search is looking for, if any.
    ///
    /// The reported bytes are borrowed from the search and stay valid until the
    /// needle changes or the search is freed, so they are copied out here.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_get` reports other than the "no needle" case.
    pub fn needle(&self) -> Result<Option<String>> {
        let mut raw = ffi::GhosttyString {
            ptr: ptr::null(),
            len: 0,
        };
        match self.get_into(ffi::GHOSTTY_SEARCH_DATA_NEEDLE, &mut raw) {
            Ok(()) => {}
            Err(err) if err.is_empty_value() => return Ok(None),
            Err(err) => return Err(err),
        }
        if raw.ptr.is_null() || raw.len == 0 {
            return Ok(None);
        }
        // SAFETY: `ptr`/`len` describe readable bytes the search keeps valid until
        // the needle changes; the copy happens immediately.
        let bytes = unsafe { core::slice::from_raw_parts(raw.ptr, raw.len) };
        Ok(Some(String::from_utf8_lossy(bytes).into_owned()))
    }

    /// Total matches found so far on the active screen.
    ///
    /// Zero until the first feed.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_get` reports.
    pub fn total_matches(&self) -> Result<usize> {
        let mut out: usize = 0;
        self.get_into(ffi::GHOSTTY_SEARCH_DATA_TOTAL_MATCHES, &mut out)?;
        Ok(out)
    }

    /// Index of the selected match, newest first.
    ///
    /// Index 0 is the newest match, so a find bar renders `index + 1` of
    /// [`Search::total_matches`]. `Ok(None)` when nothing is selected.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_get` reports.
    pub fn selected_index(&self) -> Result<Option<usize>> {
        let mut out: usize = 0;
        match self.get_into(ffi::GHOSTTY_SEARCH_DATA_SELECTED_INDEX, &mut out) {
            Ok(()) => Ok(Some(out)),
            Err(err) if err.is_empty_value() => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// The selected match, if any.
    ///
    /// The selection is an untracked snapshot with the usual selection lifetime
    /// rules: valid until the next terminal-modifying operation. Re-read it after
    /// each feed rather than caching it.
    ///
    /// # Errors
    ///
    /// Whatever `ghostty_search_get` reports other than the "nothing selected"
    /// case.
    pub fn selected_match(&self) -> Result<Option<Selection>> {
        let mut out = Selection::sized().to_ffi();
        match self.get_into(ffi::GHOSTTY_SEARCH_DATA_SELECTED_MATCH, &mut out) {
            Ok(()) => Ok(Some(Selection::from_ffi(out))),
            Err(err) if err.is_empty_value() => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// All matches on the active screen, ordered newest to oldest.
    ///
    /// Uses the documented two-step buffer protocol: a null buffer with zero
    /// capacity reports the required count, then a correctly sized buffer
    /// receives the matches.
    ///
    /// # Errors
    ///
    /// Anything other than the expected `OUT_OF_SPACE` size query.
    pub fn matches(&self) -> Result<Vec<Selection>> {
        self.match_buffer(ffi::GHOSTTY_SEARCH_DATA_MATCHES)
    }

    /// Matches on the pages covering the viewport, for drawing highlights.
    ///
    /// The list is cached per feed, so it reflects the viewport as of the last
    /// feed. It can include matches slightly outside the visible viewport when
    /// they share a page with it; upstream notes that converting each endpoint
    /// with the terminal's viewport-coordinate conversion clips these naturally.
    ///
    /// # Errors
    ///
    /// Anything other than the expected `OUT_OF_SPACE` size query.
    pub fn viewport_matches(&self) -> Result<Vec<Selection>> {
        self.match_buffer(ffi::GHOSTTY_SEARCH_DATA_VIEWPORT_MATCHES)
    }

    /// The text of the selected match.
    ///
    /// Uses `ghostty_terminal_selection_format_alloc`, because a match is a
    /// selection and the selection formatter is the supported way to read a
    /// selection's text.
    ///
    /// # Errors
    ///
    /// [`GhosttyError::InvalidValue`] for a mismatched terminal;
    /// [`GhosttyError::NoValue`] when nothing is selected; plus whatever the
    /// formatter reports.
    pub fn selected_text(&self, terminal: &Terminal) -> Result<Option<String>> {
        self.check_terminal(terminal)?;
        let Some(selection) = self.selected_match()? else {
            return Ok(None);
        };

        let mut options = ffi::GhosttyTerminalSelectionFormatOptions {
            size: 0,
            emit: ffi::GHOSTTY_FORMATTER_FORMAT_PLAIN,
            unwrap: false,
            trim: false,
            selection: ptr::null(),
        };
        options.size = core::mem::size_of::<ffi::GhosttyTerminalSelectionFormatOptions>();
        let raw_selection = selection.to_ffi();
        options.selection = &raw_selection;

        let mut out_ptr: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        // SAFETY: `terminal.as_raw()` is live; the allocator is the library
        // default; `options.selection` points at `raw_selection`, which outlives
        // the call; both out-parameters are valid.
        let code = unsafe {
            ffi::ghostty_terminal_selection_format_alloc(
                terminal.as_raw(),
                ptr::null(),
                options,
                &mut out_ptr,
                &mut out_len,
            )
        };
        GhosttyError::from_result(code)?;

        let buffer = crate::sys::OwnedBuffer::from_raw(out_ptr, out_len, Allocator::default())?;
        Ok(Some(buffer.to_string_lossy()))
    }

    /// Raw handle, for passing to sibling C APIs.
    pub fn as_raw(&self) -> ffi::GhosttySearch {
        self.raw
    }

    // ---- Private plumbing --------------------------------------------------

    /// Reject a terminal that is not the one this search was created against.
    ///
    /// The C layer would happily search whatever terminal it captured, so
    /// catching a mismatched argument here turns "silently searched the wrong
    /// thing" into a clear error.
    fn check_terminal(&self, terminal: &Terminal) -> Result<()> {
        if terminal.as_raw() != self.terminal {
            return Err(GhosttyError::InvalidValue);
        }
        Ok(())
    }

    fn set_opt(
        &mut self,
        option: ffi::GhosttySearchOption,
        value: *const core::ffi::c_void,
    ) -> Result<()> {
        // SAFETY: `self.raw` is live. `value` is NULL for the action and clear
        // options, or a pointer to a value of the documented type that outlives
        // this call.
        let code = unsafe { ffi::ghostty_search_set(self.raw, option, value) };
        GhosttyError::from_result(code)
    }

    fn get_into<T>(&self, key: ffi::GhosttySearchData, out: &mut T) -> Result<()> {
        // SAFETY: `self.raw` is live and `out` matches the key's documented
        // output type.
        let code = unsafe {
            ffi::ghostty_search_get(self.raw, key, (out as *mut T).cast::<core::ffi::c_void>())
        };
        GhosttyError::from_result(code)
    }

    /// Shared implementation of the two match-list queries.
    fn match_buffer(&self, key: ffi::GhosttySearchData) -> Result<Vec<Selection>> {
        let mut query = ffi::GhosttySelectionBuffer {
            ptr: ptr::null_mut(),
            cap: 0,
            len: 0,
        };
        match self.get_into(key, &mut query) {
            // The documented size query: NULL with cap 0 asks for the capacity.
            Ok(()) | Err(GhosttyError::OutOfSpace { .. }) => {}
            Err(err) => return Err(err),
        }
        if query.len == 0 {
            return Ok(Vec::new());
        }

        // `GhosttySelection` is plain-old-data and `Copy`, so a zeroed vector is
        // a valid initial state for the library to overwrite.
        let mut storage = vec![Selection::sized().to_ffi(); query.len];
        let mut buffer = ffi::GhosttySelectionBuffer {
            ptr: storage.as_mut_ptr(),
            cap: storage.len(),
            len: 0,
        };
        self.get_into(key, &mut buffer)?;
        if buffer.len > storage.len() {
            // The library over-reported; refuse rather than read past the Vec.
            return Err(GhosttyError::InvalidValue);
        }

        Ok(storage[..buffer.len]
            .iter()
            .map(|raw| Selection::from_ffi(*raw))
            .collect())
    }
}

impl Drop for Search {
    fn drop(&mut self) {
        if self.raw.is_null() {
            return;
        }
        // SAFETY: `self.raw` is a live search owned solely by `self`, and this is
        // the only place it is freed. The call releases tracked state the search
        // held inside the terminal but does not free the terminal.
        unsafe { ffi::ghostty_search_free(self.raw) };
        self.raw = ptr::null_mut();
    }
}
