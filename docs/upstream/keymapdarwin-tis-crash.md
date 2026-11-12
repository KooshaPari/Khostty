# Upstream report draft: `input.KeymapDarwin` test crashes inside HIToolbox

**Status: NOT FILED.** This is a ready-to-submit draft. Filing an issue against `ghostty-org/ghostty`
from this account is forbidden by standing operator policy (fork-only discipline: no `gh issue create`,
`gh pr create`, `gh discussion create`, or `gh api POST/PATCH/DELETE` against an upstream repo). The
operator files this manually, or not at all. Everything below is measured; nothing is inferred beyond
what is labelled as a hypothesis.

- Target: `ghostty-org/ghostty` @ `fa70e8b28d84d8b7e30db31c176e55b5e9c851f5`
- File: `src/input/KeymapDarwin.zig` (test block at line 257 upstream, same line in this fork)
- Fork that observed it: `KooshaPari/Khostty` @ `74cc09d2b`
- Local reproduction record: `ISSUE-114-ROOTCAUSE.md` in the fork's audit scratch

---

## Suggested title

```
input: KeymapDarwin test segfaults inside HIToolbox/CF intermittently (1 crash in 5 full runs)
```

## Environment

|                 |                                                                    |
| --------------- | ------------------------------------------------------------------ |
| OS              | macOS 27.0 (build 26A5353q), arm64                                 |
| Zig             | 0.16.0                                                             |
| Build           | `zig build test` (Debug), `-Dapp-runtime=none`                     |
| Runner          | the standard `zig` test runner, `ghostty-test`, 3 982 tests        |
| Metal toolchain | not installed; OpenGL renderer fallback, macOS Xcode suite skipped |

## What happens

`zig build test` aborts on an unnamed test in `src/input/KeymapDarwin.zig`. Observed rate: **1 crash in
5 full unfiltered runs** on this machine. That is a small sample, so treat the true rate as uncertain;
all that is established is that it is intermittent, not that it is exactly 1-in-5.

I have not measured the rate under `-Dtest-filter`. I tried, and then stopped: on this tree
`-Dtest-filter` reduces the build to a 75-test artifact, and a filter that matches nothing produces the
same 75-test artifact, so a passing filtered run does not demonstrate that this test ran at all. I am
not going to report a filtered sample as if it were evidence.

```
error: 'input.KeymapDarwin.test_0' terminated with signal ABRT with stderr:
       Segmentation fault at address 0x8
       ???:?:?: 0x19402c254 in ??? (CoreFoundation)
       ???:?:?: 0x193eec113 in ??? (CoreFoundation)
       ???:?:?: 0x193efcc63 in ??? (CoreFoundation)
       ???:?:?: 0x1a12cadc7 in ??? (HIToolbox)
       ???:?:?: 0x1a12519b7 in ??? (HIToolbox)
       ???:?:?: 0x1a1252e37 in ??? (HIToolbox)
       ???:?:?: 0x1a13cf1ab in ??? (HIToolbox)
       ???:?:?: 0x1a1259433 in ??? (HIToolbox)
       ???:?:?: 0x1a1258657 in ??? (HIToolbox)
       ???:?:?: 0x1a12594db in ??? (HIToolbox)
       ???:?:?: 0x1a124e59f in ??? (HIToolbox)
       ???:?:?: 0x1a13c2c9f in ??? (HIToolbox)
       ???:?:?: 0x1a13c6e9f in ??? (HIToolbox)
       ???:?:?: 0x1a124b373 in ??? (HIToolbox)
       ???:?:?: 0x1a13c4a87 in ??? (HIToolbox)
       ???:?:?: 0x1a13c70e3 in ??? (HIToolbox)
       ???:?:?: 0x1a124b697 in ??? (HIToolbox)
       ???:?:?: 0x1a12955e7 in ??? (HIToolbox)
       ???:?:?: 0x10a7e3bfb in ??? (ghostty-test)
       ???:?:?: 0x10a7e3df3 in ??? (ghostty-test)
       ???:?:?: 0x10a7e3efb in ??? (ghostty-test)
       ???:?:?: 0x1059a2957 in ??? (ghostty-test)
       ???:?:?: 0x1059a3007 in ??? (ghostty-test)
       ???:?:?: 0x1059a0dcb in ??? (ghostty-test)
       ???:?:?: 0x193ac0913 in start (/usr/lib/dyld)
```

`Build Summary: 100/102 steps succeeded (1 failed); 3956/3982 tests passed (25 skipped, 1 crashed)`

## Reading the stack

Bottom-up: `dyld start` -> main -> test-runner loop -> test body -> `init` -> `reinit` -> the extern
call -> 16 HIToolbox frames -> 3 CoreFoundation frames, the innermost faulting on a read at `0x8`.

The only HIToolbox call `reinit` makes before touching anything else is
`TISCopyCurrentKeyboardLayoutInputSource` (line 99). So the entry point is that call, and the 16-frame
HIToolbox descent is HIToolbox walking its own input-source state. The `0x8` read inside CoreFoundation
is what dereferencing offset 8 of a null or freed structure looks like.

No project code appears on the faulting side of the boundary. The test body is `init()` + `deinit()`.

## The minimal reproduction is negative

I extracted the exact API sequence into a standalone C program with no project code:

```c
TISInputSourceRef src = TISCopyCurrentKeyboardLayoutInputSource();
CFDataRef d = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData);
CFRelease(src);
```

200 000 iterations per process, run as 6 concurrent processes at three CPU-load tiers (0, 4 and 8
`yes` burners):

| Load tier | Processes | Iterations each | Result       |
| --------- | --------- | --------------- | ------------ |
| 0 burners | 6         | 200 000         | 6/6 `exit=0` |
| 4 burners | 6         | 200 000         | 6/6 `exit=0` |
| 8 burners | 6         | 200 000         | 6/6 `exit=0` |

**18 runs, 18 clean, 3.6 million copy+release cycles, zero faults.** So the crash is not reachable
from the API sequence alone, and is not simply "TIS under load". It depends on what the process has
already done. The suite has run ~3 950 tests by that point, several of which do CoreFoundation work
(the same log shows `shell_integration` tests emitting file-not-found warnings immediately above the
crash).

I want to be explicit that this is a hypothesis, not a finding: I have not proven that a prior test
corrupts HIToolbox's cached state, only that the identical API usage in a fresh process does not crash.

## Two hypotheses I ruled out, in case they are useful

1. **Off-main-thread TIS.** Not it. The Zig test runner executes test bodies from `pub fn main` in
   `compiler/test_runner.zig`; there is no `std.Thread.spawn` on the test path. Tests run on the main
   thread, which is what TIS wants.
2. **`src/os/cf_release_thread.zig`.** Not it. That thread pools `CFTypeRef` releases for the renderer,
   and its only consumer is `src/font/shaper/coretext.zig`. `src/input/` never references it;
   `KeymapDarwin` calls `CFRelease` directly on the calling thread.

## A separate, real bug in the same function

Independent of the crash, `reinit` leaks and `init` has no `errdefer`:

```zig
// src/input/KeymapDarwin.zig:98
fn reinit(self: *Keymap) !void {
    self.source = TISCopyCurrentKeyboardLayoutInputSource() orelse
        return Error.GetInputSourceFailed;          // +1 retained

    self.unicode_layout = layout: {
        const data_raw = TISGetInputSourceProperty(
            self.source,
            kTISPropertyUnicodeKeyLayoutData,
        ) orelse return Error.GetInputSourceFailed; // leaks self.source
```

```zig
// src/input/KeymapDarwin.zig:61
pub fn init() !Keymap {
    var keymap: Keymap = .{ .source = undefined, .unicode_layout = undefined };
    try keymap.reinit();      // on error nothing releases keymap.source
    return keymap;
}
```

One `CFTypeRef` leaks per failure and the struct is left partially initialized. This does not cause
the crash (the test only calls `deinit` after `init` succeeds, and a leak does not fault), but it is
worth fixing while the function is open.

## Why the test cannot catch this

The test's assertions are commented out with the note that they depend on the user-selected keyboard
layout, so its entire assertion surface is "`init()` and `deinit()` do not crash". That is a reasonable
thing to assert; the problem is that the one behaviour it does observe is the flaky crash.

## Possible directions (not demands)

- Make the test assert something layout-independent, so a green result means more than "did not crash".
  `sourceId()` returning a non-empty string is layout-independent.
- Fix the `reinit`/`init` error path above.
- If the HIToolbox state is genuinely being corrupted by an earlier test, running the suite with a
  heap canary or under ASan may localize it faster than anything I can do from outside.

## What I have not done

I have not bisected which test runs immediately before the crash, and I have not attempted an ASan
build. If a maintainer wants either, say so and I will run it against this environment and report the
raw output.
