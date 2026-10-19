# Current state and user journey

Source `4c9e4c57a1138087053ba740083bb2d665348b6d`; observed 2026-10-16 Pacific.

```text
identify fork artifact -> isolated install/update -> open real window
                                                   |
                       type -> shell/PTY -> VT state -> render
                                                   |
                 resize/paste/cancel -> child cleanup -> restart
                                                   |
                  local authenticated agent/binding consumer
```

| Stage                      | Main/source evidence                                                                                        | Acceptance boundary                                                                                   |
| -------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Obtain package             | v0.1.0 GitHub release contains Windows installer,Mac archive,Linux packages and WASM archive                | Published package is older than current main; signature/current install not verified                  |
| Install Windows            | September19 receipt's installer hash matches published asset digest;files installed and cleanly uninstalled | Historical verifier target was removed;no current desk installation claim                             |
| Open native Windows window | `src/apprt/windows/App.zig` init/registerWindowClass/run return Unimplemented                               | Current main is not a qualified native terminal desktop                                               |
| Execute Windows CLI/DLL    | September19 `+version` reports old `5a85344f0`;VT DLL lifecycle receipt                                     | CLI/version and VT memory operations do not exercise window,shell or renderer                         |
| Native Windows candidate   | PR33 implements window,software renderer,shared input encoders and ConPTY;PR body records native checks     | Unmerged draft;no GUI launch;IME,selection/copy,SGR,cell metrics and full Surface integration open    |
| Shell/window lifetime      | Candidate uses off-UI-thread ConPTY and kill-on-close job                                                   | Real final-artifact Ctrl-C,close,crash,restart,child cleanup and WSL/shell variants remain unaccepted |
| Agent control              | Protocol/parser/auth/server/fake-host components and documented local socket contract                       | Real app-host wiring/consumer path not qualified here;Windows named-pipe work remains PR29 candidate  |
| macOS terminal             | Upstream AppKit/Swift runtime inherited;README records older interactive launch                             | Current fork binary/source identity and regression receipt UNKNOWN;not evidence of Windows readiness  |
| Linux/BSD terminal         | Upstream GTK runtime inherited;older package/headless receipts                                              | Native window and arm64/Linux breadth remain open in platform documentation;no current parity grade   |
| Bindings                   | Rust/Go/Python/WASM source and older test/package claims                                                    | Current ABI/native artifact/profile consumers need a coherent release receipt                         |

## Windows gaps that prevent the requested finish

- **Lifecycle/renderer stubs on main.** Buildable enums,PE metadata and `+version` cannot substitute for creating a window and showing a shell. Candidate PR33 must be reviewed and integrated before its behavior belongs to main.
- **Candidate integration and frontend correctness.** PR33 explicitly lists manual key/layout,IME,copy/selection,SGR,font-cell metrics,complete core Surface and WSL/shell variants as incomplete or unverified. A glyph-availability test alone cannot qualify a terminal's layout or interaction.
- **Installer versus installed product identity.** Published installer SHA256 `4070e89e8f693c44abda13da1b718dca4e53d73279f3d945854431d76f095546` matches the historical receipt. Current desk executable hash,version,path and updater remain UNKNOWN. PR30 reports a newer candidate installer but also a GUI failure and test timeout;do not combine its receipt with PR33 into an imaginary accepted artifact.
- **IPC reachability and semantics.** Protocol v1's `pane.write` writes VT bytes into the parser,not keystrokes into the child. Do not advertise shell command input from that method. Windows same-user named-pipe transport needs an accepted implementation and negative controls.
- **Non-vacuous assurance.** `conformance/harness.c` performs plaintext comparison only when `expected_plain` is nonempty. Nontextual cases with empty expectations can pass without checking the intended mode/OSC/graphics state. The reported corpus pass count is not equivalent to that many behavioral assertions.
- **Status-language drift.** README says Windows DONE(build/exec) while PLATFORMS says PARTIAL/no window and RELEASE disclaims GA. Retain all valid historical results,but use the actual native journey as the public finish criterion.

## Fork identity and divergence

Local and queried origin main matched the source above. Local `upstream/main` and merge-base were `b3dc3d794513c11633e7c3347935693957744e83`;the local comparison was 0 upstream-only and301 fork-only commits,343 changed files,73717 insertions and228 deletions. These figures compare the **cached local upstream ref**,not current upstream or a pure handwritten maintenance delta;docs,tests,binding additions and merge history contribute.

A separate read-only GitHub query found upstream main `e3ebb1d1bf772cf5d1bc70b5ae19e6943e33a110`. Its objects were not fetched,so current upstream ahead/behind and exact semantic delta remain UNKNOWN. Upstream push URL is `no_push`;all publication is fork-only.

The canonical checkout's pre-existing untracked audit/session directories were preserved. This assessment lives in an isolated docs worktree. No other lane's files,refs,processes or receipts were overwritten.
