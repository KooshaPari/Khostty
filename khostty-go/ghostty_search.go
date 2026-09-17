package khostty

/*
#include <stdlib.h>
#include <ghostty/vt.h>
*/
import "C"

import (
	"runtime"
	"unsafe"
)

// SearchStatus reports a search's progress.
type SearchStatus C.GhosttySearchStatus

// Search progress states.
const (
	// SearchRunning means Tick can make progress without reading the terminal.
	SearchRunning SearchStatus = C.GHOSTTY_SEARCH_STATUS_RUNNING
	// SearchFeedRequired means the search is blocked until Feed is called.
	SearchFeedRequired SearchStatus = C.GHOSTTY_SEARCH_STATUS_FEED_REQUIRED
	// SearchComplete means the search has caught up with the terminal as of
	// the last feed. Later terminal writes require another Feed; a search with
	// no needle is also complete, because there is nothing to look for.
	SearchComplete SearchStatus = C.GHOSTTY_SEARCH_STATUS_COMPLETE
)

// String returns the name of the status.
func (s SearchStatus) String() string {
	switch s {
	case SearchRunning:
		return "running"
	case SearchFeedRequired:
		return "feed_required"
	case SearchComplete:
		return "complete"
	default:
		return "unknown"
	}
}

// SearchScroll selects the viewport policy applied when a match is selected.
type SearchScroll C.GhosttySearchScroll

// Scroll policies.
const (
	// SearchScrollIfNeeded scrolls only when the selected match is off screen.
	SearchScrollIfNeeded SearchScroll = C.GHOSTTY_SEARCH_SCROLL_IF_NEEDED
	// SearchScrollNone never scrolls the viewport.
	SearchScrollNone SearchScroll = C.GHOSTTY_SEARCH_SCROLL_NONE
)

// Search finds text in a terminal, including scrollback.
//
// A Search borrows its terminal. The two may be freed in either order: if the
// terminal is freed first the search detaches and still reports what it had
// already collected, but the select options and the needle stop working.
//
// Matching is byte-exact except ASCII letters, which compare
// case-insensitively, so a needle of "error" also finds "ERROR".
//
// Access to the bound terminal must be serialized: Feed, SetNeedle, and the
// select options read it. Tick, Status, TotalMatches, and SelectedIndex only
// touch search-owned memory and are safe during concurrent terminal writes.
type Search struct {
	ptr C.GhosttySearch
	// term keeps the bound terminal alive for as long as the search is
	// reachable, so the Go finalizer cannot free it out from under the C
	// search handle.
	term *Terminal
}

// NewSearch creates a search bound to the terminal.
//
// The search starts idle with no needle, reports SearchComplete, and finds
// nothing until SetNeedle is called.
func NewSearch(t *Terminal) (*Search, error) {
	p, err := t.valid()
	if err != nil {
		return nil, err
	}

	var cs C.GhosttySearch
	if err := errno(C.ghostty_search_new(nil, &cs, p)); err != nil {
		return nil, err
	}

	s := &Search{ptr: cs, term: t}
	runtime.SetFinalizer(s, (*Search).Close)
	return s, nil
}

// Close frees the search. It is safe to call more than once, and to call on a
// nil receiver. The bound terminal is not affected.
func (s *Search) Close() error {
	if s == nil || s.ptr == nil {
		return nil
	}
	C.ghostty_search_free(s.ptr)
	s.ptr = nil
	runtime.SetFinalizer(s, nil)
	return nil
}

// SetNeedle sets the text to search for and restarts the search.
//
// Setting a needle equal (under the library's case-insensitive comparison) to
// the current one keeps existing results, so a find bar can resubmit freely.
// An empty needle clears the search and returns it to idle.
func (s *Search) SetNeedle(needle string) error {
	if s == nil || s.ptr == nil {
		return ErrInvalidValue
	}

	v, cleanup := mustString([]byte(needle))
	defer cleanup()

	return errno(C.ghostty_search_set(
		s.ptr,
		C.GHOSTTY_SEARCH_OPT_NEEDLE,
		unsafe.Pointer(&v),
	))
}

// Needle returns the current needle, or "" when none is set.
func (s *Search) Needle() (string, error) {
	if s == nil || s.ptr == nil {
		return "", ErrInvalidValue
	}

	var v C.GhosttyString
	res := C.ghostty_search_get(s.ptr, C.GHOSTTY_SEARCH_DATA_NEEDLE, unsafe.Pointer(&v))
	if res == C.GHOSTTY_NO_VALUE {
		return "", nil
	}
	if err := errno(res); err != nil {
		return "", err
	}
	if v.ptr == nil || v.len == 0 {
		return "", nil
	}
	return string(C.GoBytes(unsafe.Pointer(v.ptr), C.int(v.len))), nil
}

// Run drives the search to completion.
//
// It is a blocking one-shot convenience for single-threaded embedders: it
// always feeds at least once, then ticks and feeds until the status is
// SearchComplete. Searching a large scrollback can take a while, so
// interactive embedders should drive Feed and Tick from their event loop
// instead.
func (s *Search) Run() error {
	if s == nil || s.ptr == nil {
		return ErrInvalidValue
	}
	return errno(C.ghostty_search_run(s.ptr))
}

// Feed catches the search up with the terminal. It reads the terminal, so the
// caller must serialize it with all other access to the same terminal.
//
// Feeding is the only way the search learns about terminal changes, so keep
// feeding periodically while the search is in use, even after it reports
// SearchComplete.
func (s *Search) Feed() error {
	if s == nil || s.ptr == nil {
		return ErrInvalidValue
	}
	return errno(C.ghostty_search_feed(s.ptr))
}

// Tick makes a bounded amount of progress on already-copied data.
//
// It never reads the terminal, so it is safe while another goroutine modifies
// the terminal. Loop while the status is SearchRunning, and switch to Feed
// when it becomes SearchFeedRequired.
func (s *Search) Tick() (SearchStatus, error) {
	if s == nil || s.ptr == nil {
		return 0, ErrInvalidValue
	}

	var st C.GhosttySearchStatus
	if err := errno(C.ghostty_search_tick(s.ptr, &st)); err != nil {
		return 0, err
	}
	return SearchStatus(st), nil
}

// Status returns the current search status without reading the terminal.
func (s *Search) Status() (SearchStatus, error) {
	if s == nil || s.ptr == nil {
		return 0, ErrInvalidValue
	}

	var st C.GhosttySearchStatus
	if err := errno(C.ghostty_search_get(s.ptr, C.GHOSTTY_SEARCH_DATA_STATUS, unsafe.Pointer(&st))); err != nil {
		return 0, err
	}
	return SearchStatus(st), nil
}

// TotalMatches returns the number of matches on the active screen. It is zero
// until the first feed.
func (s *Search) TotalMatches() (int, error) {
	if s == nil || s.ptr == nil {
		return 0, ErrInvalidValue
	}

	var n C.size_t
	if err := errno(C.ghostty_search_get(s.ptr, C.GHOSTTY_SEARCH_DATA_TOTAL_MATCHES, unsafe.Pointer(&n))); err != nil {
		return 0, err
	}
	return int(n), nil
}

// SelectedIndex returns the index of the selected match and whether anything
// is selected.
//
// Index 0 is the newest match and the list runs newest to oldest, so a "k of
// n" label renders index+1 of TotalMatches.
func (s *Search) SelectedIndex() (index int, selected bool, err error) {
	if s == nil || s.ptr == nil {
		return 0, false, ErrInvalidValue
	}

	var n C.size_t
	res := C.ghostty_search_get(s.ptr, C.GHOSTTY_SEARCH_DATA_SELECTED_INDEX, unsafe.Pointer(&n))
	if res == C.GHOSTTY_NO_VALUE {
		return 0, false, nil
	}
	if e := errno(res); e != nil {
		return 0, false, e
	}
	return int(n), true, nil
}

// SelectNext selects the next match, moving toward older content: up from the
// bottom of the screen into history. It wraps around past the oldest match and
// scrolls the viewport per the scroll policy. It reads the terminal, so the
// caller must serialize it with all other access to the same terminal.
//
// It returns ErrNoValue when there are no matches.
func (s *Search) SelectNext() error { return s.selectMatch(C.GHOSTTY_SEARCH_OPT_SELECT_NEXT) }

// SelectPrev selects the previous match, moving toward newer content, wrapping
// around past the newest match. Otherwise identical to SelectNext.
func (s *Search) SelectPrev() error { return s.selectMatch(C.GHOSTTY_SEARCH_OPT_SELECT_PREV) }

func (s *Search) selectMatch(opt C.GhosttySearchOption) error {
	if s == nil || s.ptr == nil {
		return ErrInvalidValue
	}
	// The select options are documented to require a NULL value.
	return errno(C.ghostty_search_set(s.ptr, opt, nil))
}

// SetScrollPolicy sets the viewport policy used by SelectNext and SelectPrev.
// The policy persists until changed.
func (s *Search) SetScrollPolicy(policy SearchScroll) error {
	if s == nil || s.ptr == nil {
		return ErrInvalidValue
	}
	v := C.GhosttySearchScroll(policy)
	return errno(C.ghostty_search_set(
		s.ptr,
		C.GHOSTTY_SEARCH_OPT_SELECT_SCROLL,
		unsafe.Pointer(&v),
	))
}

// MatchCounts reports the total match count and the number of matches covering
// the viewport, for drawing a find bar and its highlights.
//
// The viewport list is computed during feeds and cached, so it reflects the
// viewport as of the last feed. It can include matches just outside the
// visible viewport when they share a page with it, which is how Ghostty's own
// renderer behaves. The count is obtained by querying the required buffer
// capacity rather than materialising the selections, which is why no
// selection objects cross the boundary here.
func (s *Search) MatchCounts() (total int, viewport int, err error) {
	total, err = s.TotalMatches()
	if err != nil {
		return 0, 0, err
	}

	if s == nil || s.ptr == nil {
		return 0, 0, ErrInvalidValue
	}

	// A NULL pointer with zero capacity asks the library for the required
	// number of entries instead of filling a buffer.
	var buf C.GhosttySelectionBuffer
	res := C.ghostty_search_get(s.ptr, C.GHOSTTY_SEARCH_DATA_VIEWPORT_MATCHES, unsafe.Pointer(&buf))
	switch {
	case res == C.GHOSTTY_OUT_OF_SPACE:
		// buf.len now holds the required entry capacity.
		return total, int(buf.len), nil
	case res == C.GHOSTTY_SUCCESS:
		return total, int(buf.len), nil
	default:
		return total, 0, Error(res)
	}
}
