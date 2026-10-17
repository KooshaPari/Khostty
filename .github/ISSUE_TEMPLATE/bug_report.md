---
name: Bug report
about: Report something that is broken or behaves incorrectly
title: "bug: "
labels: ["bug", "needs-triage"]
assignees: []
---

## Environment

<!-- Fill in all rows that apply; delete the rest. -->

| Field                    | Value                                                               |
| ------------------------ | ------------------------------------------------------------------- |
| Khostty version / commit | (run `khostty --version` or `khostty -v`)                           |
| OS + version             | Linux (distro + release) / macOS (version + arch) / Windows (build) |
| GPU + driver             | (e.g. Apple M2 / Intel / NVIDIA 5xx + driver version)               |
| Windowing backend        | GTK / Win32 / macOS native                                          |
| Renderer                 | OpenGL / Metal / Vulkan / Software                                  |
| Build flags              | (anything non-default in your `zig build` invocation)               |

## Reproduction steps

1.
2.
3.

Minimal `.config/ghostty/config` snippet that reproduces the issue (if config-related):

```ini
# paste here
```

## Expected behavior

## Actual behavior

## Logs / screenshots

<!-- Paste terminal output, stack traces, screenshot links. Wrap logs in ```text fences. -->

```text

```

## Regression check

- [ ] This is reproducible on `main` (HEAD).
- [ ] I bisected and the offending commit is: \_\_\_
- [ ] This also reproduces on upstream `ghostty-org/ghostty` at the same commit: yes / no / not tested

## Severity

<!-- Pick one. -->

- [ ] Crash (data loss / unusable)
- [ ] Correctness bug (wrong output, wrong state)
- [ ] UX / cosmetic
- [ ] Performance regression
- [ ] Build / packaging only

## Additional context

<!-- Anything else: related issues, workarounds tried, links to forum threads, etc. -->
