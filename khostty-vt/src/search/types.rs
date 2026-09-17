//! Value types for the search API.

use crate::ffi;

/// How far the search has progressed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum SearchStatus {
    /// The search can make progress from data it has already copied. Call
    /// [`Search::tick`].
    Running,
    /// Blocked until [`Search::feed`]. This is also the state right after a
    /// needle is set, since the search has not yet seen the terminal.
    FeedRequired,
    /// Caught up with the terminal as of the last feed.
    ///
    /// Never means finished forever: later terminal writes need another feed.
    /// A search with no needle also reports complete, since there is nothing to
    /// look for.
    Complete,
    /// A status value this binding does not know.
    Unknown(ffi::GhosttySearchStatus),
}

impl SearchStatus {
    /// Map a raw `GhosttySearchStatus`.
    pub fn from_raw(raw: ffi::GhosttySearchStatus) -> Self {
        match raw {
            ffi::GHOSTTY_SEARCH_STATUS_RUNNING => SearchStatus::Running,
            ffi::GHOSTTY_SEARCH_STATUS_FEED_REQUIRED => SearchStatus::FeedRequired,
            ffi::GHOSTTY_SEARCH_STATUS_COMPLETE => SearchStatus::Complete,
            other => SearchStatus::Unknown(other),
        }
    }
}

/// Whether selecting a match scrolls the viewport to it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SearchScroll {
    /// Scroll the viewport so the match is visible, but only if it is not
    /// already visible. This is the default.
    #[default]
    IfNeeded,
    /// Never scroll the viewport.
    None,
}

impl SearchScroll {
    /// Map a raw `GhosttySearchScroll`.
    pub fn from_raw(raw: ffi::GhosttySearchScroll) -> Self {
        match raw {
            ffi::GHOSTTY_SEARCH_SCROLL_NONE => SearchScroll::None,
            _ => SearchScroll::IfNeeded,
        }
    }

    /// Raw value for the C API.
    pub fn to_raw(self) -> ffi::GhosttySearchScroll {
        match self {
            SearchScroll::IfNeeded => ffi::GHOSTTY_SEARCH_SCROLL_IF_NEEDED,
            SearchScroll::None => ffi::GHOSTTY_SEARCH_SCROLL_NONE,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_maps_known_values_and_preserves_unknown_ones() {
        assert_eq!(
            SearchStatus::from_raw(ffi::GHOSTTY_SEARCH_STATUS_RUNNING),
            SearchStatus::Running
        );
        assert_eq!(
            SearchStatus::from_raw(ffi::GHOSTTY_SEARCH_STATUS_FEED_REQUIRED),
            SearchStatus::FeedRequired
        );
        assert_eq!(
            SearchStatus::from_raw(ffi::GHOSTTY_SEARCH_STATUS_COMPLETE),
            SearchStatus::Complete
        );
        assert_eq!(SearchStatus::from_raw(99), SearchStatus::Unknown(99));
    }

    #[test]
    fn scroll_policy_round_trips() {
        for policy in [SearchScroll::IfNeeded, SearchScroll::None] {
            assert_eq!(SearchScroll::from_raw(policy.to_raw()), policy);
        }
        assert_eq!(SearchScroll::default(), SearchScroll::IfNeeded);
    }

    #[test]
    fn scroll_from_raw_treats_unknown_values_as_the_default() {
        // The policy is a two-value enum with a documented default, so an
        // unrecognised raw value resolves to the safe, non-scrolling behaviour of
        // the documented default rather than inventing a third state.
        assert_eq!(SearchScroll::from_raw(12345), SearchScroll::IfNeeded);
        assert_eq!(
            SearchScroll::from_raw(ffi::GHOSTTY_SEARCH_SCROLL_NONE),
            SearchScroll::None
        );
    }
}
