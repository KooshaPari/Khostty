package khostty

/*
#include <ghostty/vt.h>
*/
import "C"

// TerminalData identifies a typed field readable from a Terminal with
// Terminal.Data or one of its typed accessors.
//
// The concrete Go/C type of each field is documented per constant; passing a
// pointer of the wrong type to Terminal.Data is undefined behaviour.
type TerminalData C.GhosttyTerminalData

// Terminal data fields. The comment on each names the output type.
const (
	// DataCols is the terminal width in cells. Output type: *uint16.
	DataCols TerminalData = C.GHOSTTY_TERMINAL_DATA_COLS
	// DataRows is the terminal height in cells. Output type: *uint16.
	DataRows TerminalData = C.GHOSTTY_TERMINAL_DATA_ROWS
	// DataCursorX is the cursor column. Output type: *uint16.
	DataCursorX TerminalData = C.GHOSTTY_TERMINAL_DATA_CURSOR_X
	// DataCursorY is the cursor row. Output type: *uint16.
	DataCursorY TerminalData = C.GHOSTTY_TERMINAL_DATA_CURSOR_Y
	// DataCursorPendingWrap reports deferred wrap at the last column. Output type: *C.bool.
	DataCursorPendingWrap TerminalData = C.GHOSTTY_TERMINAL_DATA_CURSOR_PENDING_WRAP
	// DataActiveScreen is the active screen buffer. Output type: *Screen.
	DataActiveScreen TerminalData = C.GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN
	// DataCursorVisible reports cursor visibility. Output type: *C.bool.
	DataCursorVisible TerminalData = C.GHOSTTY_TERMINAL_DATA_CURSOR_VISIBLE
	// DataKittyKeyboardFlags is the Kitty keyboard protocol flags. Output type: *uint8.
	DataKittyKeyboardFlags TerminalData = C.GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS
	// DataScrollbar is the scrollbar state. Output type: *C.GhosttyTerminalScrollbar.
	DataScrollbar TerminalData = C.GHOSTTY_TERMINAL_DATA_SCROLLBAR
	// DataCursorStyle is the cursor's SGR style, not its shape.
	// Output type: *C.GhosttyStyle; use Terminal.CursorStyle for the Go value.
	DataCursorStyle TerminalData = C.GHOSTTY_TERMINAL_DATA_CURSOR_STYLE
	// DataMouseTracking reports mouse reporting state. Output type: *C.bool.
	DataMouseTracking TerminalData = C.GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING
	// DataTitle is the OSC 0/2 title. Output type: *C.GhosttyString.
	DataTitle TerminalData = C.GHOSTTY_TERMINAL_DATA_TITLE
	// DataPwd is the OSC 7 working directory. Output type: *C.GhosttyString.
	DataPwd TerminalData = C.GHOSTTY_TERMINAL_DATA_PWD
	// DataTotalRows counts screen plus scrollback rows. Output type: *C.size_t.
	DataTotalRows TerminalData = C.GHOSTTY_TERMINAL_DATA_TOTAL_ROWS
	// DataScrollbackRows counts scrollback rows. Output type: *C.size_t.
	DataScrollbackRows TerminalData = C.GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS
	// DataWidthPx is the width in pixels. Output type: *uint32.
	DataWidthPx TerminalData = C.GHOSTTY_TERMINAL_DATA_WIDTH_PX
	// DataHeightPx is the height in pixels. Output type: *uint32.
	DataHeightPx TerminalData = C.GHOSTTY_TERMINAL_DATA_HEIGHT_PX
	// DataColorForeground is the effective foreground color. Output type: *C.GhosttyColorRgb.
	DataColorForeground TerminalData = C.GHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND
	// DataColorBackground is the effective background color. Output type: *C.GhosttyColorRgb.
	DataColorBackground TerminalData = C.GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND
	// DataColorCursor is the effective cursor color. Output type: *C.GhosttyColorRgb.
	DataColorCursor TerminalData = C.GHOSTTY_TERMINAL_DATA_COLOR_CURSOR
	// DataColorPalette is the 256-entry palette. Output type: *[256]C.GhosttyColorRgb.
	DataColorPalette TerminalData = C.GHOSTTY_TERMINAL_DATA_COLOR_PALETTE
	// DataVTGround reports whether the VT parser is at a stateless point. Output type: *C.bool.
	DataVTGround TerminalData = C.GHOSTTY_TERMINAL_DATA_VT_GROUND
	// DataCursorAtPrompt reports whether the cursor is at a semantic prompt. Output type: *C.bool.
	DataCursorAtPrompt TerminalData = C.GHOSTTY_TERMINAL_DATA_CURSOR_AT_PROMPT
	// DataContinuationMaxBytes is the configured continuation limit. Output type: *C.size_t.
	DataContinuationMaxBytes TerminalData = C.GHOSTTY_TERMINAL_DATA_CONTINUATION_MAX_BYTES
	// DataClipboardWriteMaxBytes is the Kitty clipboard write limit. Output type: *C.size_t.
	DataClipboardWriteMaxBytes TerminalData = C.GHOSTTY_TERMINAL_DATA_CLIPBOARD_WRITE_MAX_BYTES
)

// TerminalOption identifies a writable terminal option.
//
// Pointer-valued options are written with Terminal.SetOption; string and
// scalar options have typed helpers on Terminal.
type TerminalOption C.GhosttyTerminalOption

// Terminal options. The comment on each names the input type.
const (
	// OptUserdata is the userdata handed to every callback. Input type: unsafe.Pointer.
	OptUserdata TerminalOption = C.GHOSTTY_TERMINAL_OPT_USERDATA
	// OptWritePty receives VT query and mode-report output. Input type: GhosttyTerminalWritePtyFn.
	OptWritePty TerminalOption = C.GHOSTTY_TERMINAL_OPT_WRITE_PTY
	// OptBell receives BEL. Input type: GhosttyTerminalBellFn.
	OptBell TerminalOption = C.GHOSTTY_TERMINAL_OPT_BELL
	// OptEnquiry receives ENQ. Input type: GhosttyTerminalEnquiryFn.
	OptEnquiry TerminalOption = C.GHOSTTY_TERMINAL_OPT_ENQUIRY
	// OptXtversion receives XTVERSION queries. Input type: GhosttyTerminalXtversionFn.
	OptXtversion TerminalOption = C.GHOSTTY_TERMINAL_OPT_XTVERSION
	// OptTitleChanged receives OSC 0/2 title changes. Input type: GhosttyTerminalTitleChangedFn.
	OptTitleChanged TerminalOption = C.GHOSTTY_TERMINAL_OPT_TITLE_CHANGED
	// OptSize receives XTWINOPS size queries. Input type: GhosttyTerminalSizeFn.
	OptSize TerminalOption = C.GHOSTTY_TERMINAL_OPT_SIZE
	// OptColorScheme receives color-scheme queries. Input type: GhosttyTerminalColorSchemeFn.
	OptColorScheme TerminalOption = C.GHOSTTY_TERMINAL_OPT_COLOR_SCHEME
	// OptDeviceAttributes receives device-attribute queries. Input type: GhosttyTerminalDeviceAttributesFn.
	OptDeviceAttributes TerminalOption = C.GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES
	// OptTitle sets the initial title. Input type: *C.GhosttyString.
	OptTitle TerminalOption = C.GHOSTTY_TERMINAL_OPT_TITLE
	// OptPwd sets the initial working directory. Input type: *C.GhosttyString.
	OptPwd TerminalOption = C.GHOSTTY_TERMINAL_OPT_PWD
	// OptColorForeground sets the default foreground. Input type: *C.GhosttyColorRgb.
	OptColorForeground TerminalOption = C.GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND
	// OptColorBackground sets the default background. Input type: *C.GhosttyColorRgb.
	OptColorBackground TerminalOption = C.GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND
	// OptColorCursor sets the default cursor color. Input type: *C.GhosttyColorRgb.
	OptColorCursor TerminalOption = C.GHOSTTY_TERMINAL_OPT_COLOR_CURSOR
	// OptColorPalette sets the default palette. Input type: *[256]C.GhosttyColorRgb.
	OptColorPalette TerminalOption = C.GHOSTTY_TERMINAL_OPT_COLOR_PALETTE
	// OptKittyImageStorageLimit sets the Kitty image storage budget. Input type: *C.size_t.
	OptKittyImageStorageLimit TerminalOption = C.GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT
	// OptKittyImageMediumFile toggles file-backed Kitty images. Input type: *C.bool.
	OptKittyImageMediumFile TerminalOption = C.GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_FILE
	// OptKittyImageMediumTempFile toggles temp-file-backed Kitty images. Input type: *C.bool.
	OptKittyImageMediumTempFile TerminalOption = C.GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_TEMP_FILE
	// OptKittyImageMediumSharedMem toggles shared-memory Kitty images. Input type: *C.bool.
	OptKittyImageMediumSharedMem TerminalOption = C.GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_MEDIUM_SHARED_MEM
	// OptAPCMaxBytes sets the generic APC byte limit. Input type: *C.size_t.
	OptAPCMaxBytes TerminalOption = C.GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES
	// OptAPCMaxBytesKitty sets the Kitty APC byte limit. Input type: *C.size_t.
	OptAPCMaxBytesKitty TerminalOption = C.GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES_KITTY
	// OptSelection installs the selection handle. Input type: *C.GhosttySelection.
	OptSelection TerminalOption = C.GHOSTTY_TERMINAL_OPT_SELECTION
	// OptDefaultCursorStyle sets the default cursor shape. Input type: *C.GhosttyTerminalCursorStyle
	// (a CursorShape value).
	OptDefaultCursorStyle TerminalOption = C.GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_STYLE
	// OptDefaultCursorBlink sets default cursor blinking. Input type: *C.bool.
	OptDefaultCursorBlink TerminalOption = C.GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_BLINK
	// OptGlyphProtocol sets the glyph protocol. Input type: *C.GhosttyTerminalGlyphProtocol.
	OptGlyphProtocol TerminalOption = C.GHOSTTY_TERMINAL_OPT_GLYPH_PROTOCOL
	// OptPwdChanged installs a pwd-changed callback. Input type: GhosttyTerminalPwdChangedFn.
	OptPwdChanged TerminalOption = C.GHOSTTY_TERMINAL_OPT_PWD_CHANGED
	// OptClipboardWrite installs a clipboard-write callback. Input type: GhosttyTerminalClipboardWriteFn.
	OptClipboardWrite TerminalOption = C.GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE
	// OptScrollbackMaxBytes sets the scrollback byte budget. Input type: *C.size_t.
	OptScrollbackMaxBytes TerminalOption = C.GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES
	// OptScrollbackMaxLines sets the scrollback line budget. Input type: *C.size_t.
	OptScrollbackMaxLines TerminalOption = C.GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES
	// OptDesktopNotification installs a notification callback. Input type: GhosttyTerminalDesktopNotificationFn.
	OptDesktopNotification TerminalOption = C.GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION
	// OptProgressReport installs an OSC 9;4 progress callback. Input type: GhosttyTerminalProgressReportFn.
	OptProgressReport TerminalOption = C.GHOSTTY_TERMINAL_OPT_PROGRESS_REPORT
	// OptContinuationMaxBytes sets the continuation byte limit. Input type: *C.size_t.
	OptContinuationMaxBytes TerminalOption = C.GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES
	// OptTitleReport enables title reporting. Input type: *C.bool.
	OptTitleReport TerminalOption = C.GHOSTTY_TERMINAL_OPT_TITLE_REPORT
	// OptModeDefault sets a default for a terminal mode. Input type: *C.GhosttyTerminalModeConfig.
	OptModeDefault TerminalOption = C.GHOSTTY_TERMINAL_OPT_MODE_DEFAULT
	// OptMode forces a terminal mode value. Input type: *C.GhosttyTerminalModeConfig.
	OptMode TerminalOption = C.GHOSTTY_TERMINAL_OPT_MODE
	// OptUnknownSequence installs an unknown-sequence callback. Input type: GhosttyTerminalUnknownSequenceFn.
	OptUnknownSequence TerminalOption = C.GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE
	// OptUnknownMaxBytes sets the unknown-sequence capture limit. Input type: *C.size_t.
	OptUnknownMaxBytes TerminalOption = C.GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES
	// OptTerminfoName sets the TERM value reported in queries. Input type: *C.GhosttyString.
	OptTerminfoName TerminalOption = C.GHOSTTY_TERMINAL_OPT_TERMINFO_NAME
	// OptClipboardRead installs a clipboard-read callback. Input type: GhosttyTerminalClipboardReadFn.
	OptClipboardRead TerminalOption = C.GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ
	// OptClipboardWriteMaxBytes sets the Kitty clipboard write limit. Input type: *C.size_t.
	OptClipboardWriteMaxBytes TerminalOption = C.GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE_MAX_BYTES
)

// Screen identifies which screen buffer is active.
type Screen C.GhosttyTerminalScreen

// Screen buffers.
const (
	// ScreenPrimary is the normal screen, with scrollback.
	ScreenPrimary Screen = C.GHOSTTY_TERMINAL_SCREEN_PRIMARY
	// ScreenAlternate is the alternate screen used by full-screen apps.
	ScreenAlternate Screen = C.GHOSTTY_TERMINAL_SCREEN_ALTERNATE
)

// String returns the name of the screen buffer.
func (s Screen) String() string {
	switch s {
	case ScreenPrimary:
		return "primary"
	case ScreenAlternate:
		return "alternate"
	default:
		return "unknown"
	}
}

// CursorShape identifies the cursor shape.
//
// It is the value type of the OptDefaultCursorStyle option. Note that it is
// unrelated to Terminal.CursorStyle, which returns the SGR style applied to
// newly printed characters.
type CursorShape C.GhosttyTerminalCursorStyle

// Cursor shapes.
const (
	// CursorShapeBar is a vertical bar.
	CursorShapeBar CursorShape = C.GHOSTTY_TERMINAL_CURSOR_STYLE_BAR
	// CursorShapeBlock is a filled block.
	CursorShapeBlock CursorShape = C.GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK
	// CursorShapeUnderline is an underline.
	CursorShapeUnderline CursorShape = C.GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE
	// CursorShapeBlockHollow is an outlined block.
	CursorShapeBlockHollow CursorShape = C.GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK_HOLLOW
)

// String returns the name of the cursor shape.
func (c CursorShape) String() string {
	switch c {
	case CursorShapeBar:
		return "bar"
	case CursorShapeBlock:
		return "block"
	case CursorShapeUnderline:
		return "underline"
	case CursorShapeBlockHollow:
		return "block_hollow"
	default:
		return "unknown"
	}
}
