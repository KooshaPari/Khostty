# Finite finish plan and estimates

Planning source: `4c9e4c57a1138087053ba740083bb2d665348b6d`,existing PR29/30/33 and accepted terminal/fork boundaries. Ranges are remaining engineering effort requested for planning,not historic task-count estimates or promised dates.

## Work-package estimates

One engineer-day is approximately eight focused hours including review,regression/negative controls and acceptance receipts. Existing candidate reuse,accessible native hosts and stable upstream engine interfaces are assumed. Each package excludes the others. Low/high are plausible bounds under present uncertainty,not statistical confidence intervals. No production throughput calibration exists.

| ID  | Bounded outcome and exit gate                                                                                                               | Dependencies/existing work                     | Engineer-days | Confidence                               |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------- | ---------------------------------------- |
| W0  | Freeze source/consumer/native profiles,artifact/version identity and required behavior matrix                                               | Existing platform/protocol/WBS docs;issue13/28 | 1-2           | Medium                                   |
| W1  | Integrate a coherent Windows candidate on fork;resolve overlapping build/installer/IPC changes without rewriting proven work                | W0;PR29/30/33                                  | 3-7           | Low;candidate overlap/native integration |
| W2  | Correct native window/input/render journey:real shell display,resize,Unicode,core keyboard/paste/selection and expected Surface integration | W1;PR33;issues21/22/23/25                      | 4-10          | Low;current draft explicitly incomplete  |
| W3  | Qualify shell/ConPTY and required local transport lifecycle:Ctrl-C,close/crash/cleanup,WSL/shell variants,same-user IPC denial              | W1;issues24/26;PR29/33                         | 3-7           | Low;cross-process races/native ACL       |
| W4  | Own install/update path,versioned exe/DLL/installer manifest,side-by-side upstream isolation and rollback;required signing policy resolved  | W0/W1;PR30;packaging/version scripts           | 3-6           | Medium-low                               |
| W5  | Independent real Windows install+window+shell adversarial receipt on exact final artifact;no capture requirement                            | W2/W3/W4;issue28                               | 3-6           | Low;first integrated native acceptance   |
| W6  | Preserve current Mac/Linux user/consumer behavior through fork changes;qualify required native regression profiles                          | W1;upstream runtime reuse and prior receipts   | 2-5           | Medium-low;profile breadth               |
| W7  | Close retained maturity deltas:IME/layout breadth,accessibility,DPI/fonts,performance and comparative terminal quality                      | W2/W3/W5/W6;W0 required-profile choices        | 6-12          | Low;manual/native acceptance breadth     |
| W8  | Non-vacuous VT/IPC and binding assurance:state assertions,negative controls,real app-host consumer and ABI/package match                    | W0/W1/W3;conformance and wrapper suites        | 3-7           | Low;reachability and ABI review          |
| W9  | Coherent fork-only release,platform receipts,update/rollback evidence and owned maintenance/divergence ledger                               | W4/W5/W6/W8                                    | 2-5           | Medium-low                               |

## Horizon totals

| Horizon                                                                          | Packages    | Cumulative remaining effort         |
| -------------------------------------------------------------------------------- | ----------- | ----------------------------------- |
| CVP:valuable isolated native Windows terminal,preserving current other platforms | W0-W6       | 19-43 engineer-days (152-344 hours) |
| MVP:CVP plus accepted agent/embedding consumer and coherent release assurance    | CVP + W8/W9 | 24-55 engineer-days (192-440 hours) |
| Full finite maturity:retained advanced native quality and comparative proof      | MVP + W7    | 30-67 engineer-days (240-536 hours) |

CVP is a delivery sequence,not an exemption from required keyboard/accessibility/security behavior. If W0 classifies any W7 behavior as essential for the actual target user,it moves into CVP and the CVP range increases. Proposed new platforms,protocolv2 features or a different renderer are not silently included or authorized. A major architecture replacement invalidates these ranges.

## Conditional calendar scenario

For planning only,assume two dedicated implementation engineers,independent review/native acceptance available each week,and70% effective availability after integration/review overhead. That yields about7 engineer-days/week. Pure capacity division gives CVP2.7-6.2 weeks,MVP3.4-7.9 weeks and full maturity4.3-9.6 weeks. Serial candidate integration,native fixes and acceptance windows make capacity division optimistic.

A conditional working scenario is **CVP4-9 elapsed weeks,MVP5-11 weeks,full maturity6-14 weeks**,from an actual staffed start after W0. This includes dependency/coordination allowance but excludes unknown external waiting and new scope. It is not a committed delivery date. One engineer or intermittent native access stretches elapsed time;more agents do not divide it linearly. Re-estimate after W1 and the first real-window/installed-artifact receipt rather than carrying this scenario indefinitely.

## Dependency structure and first wave

```text
W0 -> W1 -> W2 --------+
 |      +-> W3 -------+ +-> W5 -> W9
 +--------> W4 ------+       ^     ^
        W1 -> W6 ------------+-----+
 W0/W1/W3 -> W8 -------------------+
 W2/W3/W5/W6 -> W7 (retained maturity)
```

1. Integration owner compares PR29/30/33 scope and reuses the existing native candidate. Record exact head,review feedback,retained failures and one-writer ownership per shared runtime/build file.
2. Independent assurance freezes genuine Windows behavior and identifies which existing tests assert real state versus only construction/no-crash. Prepare rejection,termination and changed-ABI negatives before declaring success.
3. Packaging work can proceed separately after identity decisions;it must package the final integration binary,not join a newer installer with an older runtime receipt.
4. Run heavy builds on the designated stronger host with bounded concurrency. Capture no screenshots or recordings;use process-scoped native instrumentation,CLI output,files/logs and explicit operator acceptance where necessary.

## Required finish receipts

- Source SHA and upstream-base identity;compiler/build profile;exe/DLL/installer hashes;certificate/signature state where applicable;version from actual payload.
- Installation path,shortcut/process identity,own updater channel,side-by-side upstream behavior and rollback/uninstall observations.
- A real window belonging to that process,real shell stdout/exit/input/resize/interrupt/close/restart and child cleanup;no substitution of `+version` or DLL-only proof.
- Frozen required native/profile matrix,non-vacuous assertions,independent negative controls and real accepted agent/embedding consumer path.
- Correctness before comparative latency/resource/accessibility claims. Publish uncertainty and failed attempts;do not claim best-in-class from inherited parser features or passing test totals.
