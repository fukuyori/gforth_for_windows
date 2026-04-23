# Windows Interactive Recovery Plan

This note describes the safest path for restoring richer interactive behavior
on the Windows-native fork after the earlier failed attempt to re-enable the
status line.

The current conclusion is that Windows support should not try to make the
upstream Unix/Linux terminal stack talk directly to the Windows console.  It
should introduce an explicit Windows terminal wrapper between Gforth and the
Windows input/output mechanisms, and that wrapper should present a stable
Unix-like terminal contract to the Forth layers above it.

## Problem Statement

The failed attempt was not just a `status-line.fs` problem.

Upstream interactive behavior is built as a stack:

- `engine/io.c` and `kernel/io.fs` provide terminal-facing byte input
- `ekey.fs` turns terminal input into higher-level key events
- `history.fs` builds command-line editing and redraw behavior on top of that
- `status-line.fs` and `locate1.fs` depend on the richer editor state

The Windows-native port currently avoids that full stack during startup and
uses `kernel/saccept.fs` instead. That choice fixed practical console issues
such as double-Enter, double-echo, and newline translation problems in Windows
Terminal and WezTerm, but it also removed assumptions that the upstream editor
and status line rely on.

Therefore, the next recovery attempt should not start by re-enabling
`status-line.fs`, `history.fs`, or `ekey.fs` directly. It should start by
defining and implementing a Windows terminal wrapper that provides the parts of
a Unix/Linux interactive terminal contract that upstream Gforth expects.

## Current Code Reality

The repository already contains pieces of this wrapper, but they are implicit
and spread across several files.

- `engine/main.c` switches `stdin`, `stdout`, and `stderr` to binary mode on
  Windows so the C runtime does not turn Gforth's own `CRLF` output into
  `CRCRLF`.
- `engine/io.c` has Windows-specific key input logic using `_getch()` plus
  `CRLF`/`LFCR` suppression for console input.
- `engine/io.c` also applies newline-pair suppression for non-TTY stream input.
- `engine/support.c` still has a separate Windows `ReadConsoleA` path used by
  `read-line`.
- `startup.fs` loads `kernel/saccept.fs` on Windows instead of `ekey.fs` plus
  `history.fs`.
- `kernel/io.fs` already exposes useful Forth-side boundaries through
  `key-ior`, `key?`, `type`, `emit`, `cr`, `form`, `at-xy`, and related output
  methods.

The plan should therefore treat the first implementation step as a cleanup and
contract extraction effort, not as a large new feature. The existing Windows
behavior must remain the baseline until the wrapper is proven.

## Design Goal

The goal is not to emulate Linux as an operating system. The goal is to
emulate the parts of a Unix-like interactive terminal contract that upstream
Gforth expects.

That contract should be strong enough for:

- `ekey.fs`
- `history.fs`
- `status-line.fs`
- `locate1.fs`

to run with minimal Windows-specific forks.

The wrapper must support two modes:

- a simple mode that preserves the current `kernel/saccept.fs` startup path
- an advanced mode that can later enable selected `ekey.fs`, `history.fs`,
  `status-line.fs`, and `locate1.fs` behavior

## Required Terminal Contract

The recovery plan should target these guarantees.

### Input guarantees

- one logical Enter produces one logical newline
- `CRLF`, `LFCR`, lone `CR`, and lone `LF` have documented behavior
- newline normalization happens before higher editor layers see input
- terminal echo is controlled in one place only
- ordinary printable keys arrive predictably as single logical input events
- stream input and interactive TTY input follow compatible newline rules
- extended keys can be mapped into upstream-style `ekey` values later
- window resize can be surfaced in a form compatible with `k-winch` later

### Output guarantees

- normal text output does not duplicate or corrupt newlines
- binary-mode standard streams remain the default on Windows
- cursor save/restore and cursor movement work consistently before status-line
  redraw is enabled
- status-line redraw does not damage the current input line
- interactive redraw and ordinary output have a clear ownership boundary

### State guarantees

- screen width information exists even without full `history.fs`
- the editor width and cursor position state are available from stable entry
  points
- `.status` and `.unstatus` can be safely called even in reduced modes
- `locate1.fs` does not force unsafe status-line behavior on Windows

## Proposed Architecture

The safest architecture is a three-layer model.

### Layer 1: Windows terminal wrapper

This is the low-level boundary in `engine/io.c`, `engine/support.c`, and the
small Forth-facing pieces around `key-ior`.

Responsibilities:

- raw key collection
- newline normalization
- echo control ownership
- stream vs TTY distinction
- standard stream binary-mode policy
- cursor-control capability policy
- resize event bridging

The first implementation should make this layer explicit without changing
behavior. After that, both key input and `read-line` input should use the same
documented newline and echo contract.

### Layer 2: Editor compatibility boundary

This layer separates the Windows-native terminal behavior from the upstream
editor stack.

Responsibilities:

- define what `edit-key`, `key-ior`, and `ekey` may assume
- define how input-line redraw is requested
- provide any editor state that `status-line.fs` needs without forcing a full
  `history.fs` dependency
- keep the simple `saccept.fs` path working while advanced mode is developed

This boundary is where compatibility shims or fallback values should live.

### Layer 3: Rich interactive features

Only after Layers 1 and 2 are stable should richer features be restored:

- optional `status-line.fs`
- reduced and then richer `locate1.fs` behavior
- limited `history.fs` behavior
- selected and then broader `ekey.fs` behavior

## Recovery Strategy

The recovery should proceed in phases that preserve a working rollback point at
the end of each phase.

### Phase 0: Freeze and verify current behavior

Record the current Windows-native baseline:

- Enter is processed exactly once
- no extra `ok`
- no double echo
- no broken `CRLF`
- no regression for non-TTY input
- normal output remains stable in Windows Terminal and WezTerm

Deliverables:

- a short manual test checklist
- a baseline note describing current expected Windows behavior
  (`WINDOWS-INTERACTIVE-BASELINE.md`)
- smoke-test commands for terminal and non-terminal input

### Phase 1: Define the Windows terminal contract

Document the exact semantics expected at the wrapper and editor boundaries.

This phase should explicitly define:

- what `key-ior` returns on Windows
- what `key?` means for pending Windows console keys
- how `read-line` should match the key-input newline policy
- how newline pairs are normalized
- where echo is owned
- when standard streams are put in binary mode
- how resize is represented
- what higher layers may assume about cursor control

Deliverables:

- a contract section in the Windows docs (`WINDOWS-TERMINAL-CONTRACT.md`)
- a code map showing the current input path and output path
  (`WINDOWS-TERMINAL-CONTRACT.md`)
- a list of behavior that must not change during wrapper extraction
  (`WINDOWS-TERMINAL-CONTRACT.md`)

### Phase 2: Extract the low-level wrapper without behavior changes

Do not restore upstream editor features yet.

Instead, make the existing Windows behavior explicit and stable:

- centralize console-key pending state behind named wrapper functions
- centralize newline-pair suppression for TTY and non-TTY input
- make the TTY vs non-TTY decision visible at the wrapper boundary
- keep `saccept.fs` as the default startup path
- keep binary-mode standard streams as the Windows default
- avoid changing user-visible behavior in this phase

Deliverables:

- cleaned-up low-level Windows input/output path
- stable verification results matching Phase 0
- no change to default Windows startup behavior

### Phase 3: Align `key` and `read-line` behavior

The current code has a key-by-key path in `engine/io.c` and a separate
`ReadConsoleA` line-input path in `engine/support.c`.

Before enabling richer editor behavior, these paths should be made consistent:

- confirm whether `read-line` is still needed for Windows console input
- ensure `read-line` and `key` normalize line endings the same way
- ensure echo ownership is not different between the two paths
- preserve non-TTY stream behavior

Deliverables:

- one documented newline policy for both character and line input
- tests or checklist entries covering console, pipe, and redirected input
- Phase 3 recheck results in `WINDOWS-INTERACTIVE-BASELINE.md`

### Phase 4: Decouple `status-line.fs` from full `history.fs`

The failed attempt strongly suggests that `status-line.fs` should not be
restored by directly re-enabling the full upstream startup path.

Instead:

- identify the minimum state it actually needs
- provide that state through a smaller compatibility boundary
- make status-line startup optional on Windows first
- ensure `.status` and `.unstatus` are safe in reduced modes

Important point:

`status-line.fs` currently uses values such as `edit-linew` and `screenw`.
`edit-linew` exists in the general input stack, but `screenw` currently comes
from `history.fs`. That dependency should be reduced or wrapped before the
status line is made part of the default Windows startup experience.

Deliverables:

- a Windows-safe status-line mode
- preferably opt-in first, not default-on
- no dependency on full `history.fs` for basic status-line safety
- Phase 4 recheck results in `WINDOWS-INTERACTIVE-BASELINE.md`

### Phase 5: Repair `locate1.fs` integration

`locate1.fs` currently requires `status-line.fs` and has richer interactive
scrolling that depends on `ekey` behavior.

This should be cleaned up after the status line itself is stable.

Recommended direction:

- keep a reduced locate mode that works without advanced input
- avoid forcing unsafe status-line startup on Windows
- only enable richer `ekey` navigation when the terminal contract is proven

Deliverables:

- explicit reduced-mode behavior on Windows
- conditional richer behavior when compatibility is enabled
- Phase 5 recheck results in `WINDOWS-INTERACTIVE-BASELINE.md`

### Phase 6: Restore richer editor behavior selectively

Only after the terminal contract, wrapper, and status-line integration are
stable should larger parts of the upstream editor stack be considered.

Phase 6 has an additional prerequisite in the current Windows native image:
the image does not currently expose several startup-level words such as
`locate`, `ekey`, `history-cold`, or `see`, and runtime `require` of those
source files fails on missing build/startup-context dependencies.  Therefore,
the first Phase 6 task is not to enable history or `ekey` directly; it is to
define a safe advanced-interactive image or loading path.

Use `scripts/check-advanced-interactive-readiness.ps1` to repeat the current
readiness checks before changing the image/loading path.
Use `scripts/classify-advanced-interactive-blockers.ps1` to classify the
current blockers by missing word, startup/build-context dependency, image
builder mismatch, or compact-image compile limitation.
Use `scripts/build-advanced-interactive-image.ps1 -ProbeOnly` to check whether
the local native image and bootstrap Gforth can currently build a separate
advanced-interactive image.
Use `windows-interactive-advanced.fs` as the conservative runtime-loader
entrypoint while the image-builder path is unresolved.  In the current compact
image it performs top-level opt-in reporting when `GFORTH_WIN_ADVANCED=1` and
loads only reduced-safe modules such as `status-line.fs` and `locate1.fs`; it
does not activate the full advanced editor behavior.
Use `GFORTH_WIN_ADVANCED_QUIET=1` for scripted post-loader checks.
Use `scripts/probe-reduced-interactive.ps1` to verify the reduced interactive
path.  The current implementation records accepted lines
only when `GFORTH_WIN_HISTORY=1` is set, writes to `GFORTH_WIN_HISTORY_FILE`
when provided, supports opt-in `Ctrl-P` previous-line recall with
`GFORTH_WIN_HISTORY_NAV=1`, supports selected opt-in ANSI escape sequences
with `GFORTH_WIN_EKEY=1`, surfaces compact opt-in `k-winch` handling with
`GFORTH_WIN_WINCH=1`, can enable the reduced group with
`GFORTH_WIN_INTERACTIVE=1`, and still keeps full `history.fs` disabled.
`scripts/probe-saccept-history-persistence.ps1` remains as the compatibility
entrypoint for the same check.
Use `scripts/check-windows-interactive-release.ps1` as the release-facing
entrypoint for the reduced stack; it runs the automated checks and prints the
manual Windows Terminal / WezTerm checklist.
The same checks can also be requested after a native build with:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe" -CheckWindowsInteractiveRelease
```

These switches are intentionally opt-in and must not change the default
`kernel/saccept.fs` startup path.

Suggested order:

1. classify advanced stack blockers and keep the report repeatable
2. make reduced `status-line.fs` and `locate1.fs` safe to load in the compact
   image
3. define the advanced-interactive image/loading path
4. probe reduced `saccept.fs` history persistence primitives
5. history persistence only, without full `history.fs`
6. limited history navigation with opt-in `Ctrl-P` recall
7. selected `ekey` support for Up, safe Down, and safe PageUp/PageDown
8. resize events surfaced as compact opt-in `k-winch`
9. integrated reduced interactive opt-in flag and manual test path
10. release-facing automated and manual check entrypoint
11. broader editor parity with upstream

This order keeps the riskiest integration work last.

## Safety Rules

The implementation should follow these rules.

- Keep the current `saccept.fs` startup path as the default until the new path
  is proven.
- Treat wrapper extraction as a no-behavior-change refactor first.
- Put richer behavior behind explicit feature flags or a Windows-specific
  startup toggle first.
- Do not restore `history.fs` and `ekey.fs` wholesale in one step.
- Treat `locate1.fs` as a separate consumer of the terminal contract, not as
  proof that the base REPL is correct.
- Do not let `status-line.fs` depend on full `history.fs` just to obtain basic
  width or redraw state.
- Preserve a clean rollback point after each phase.

## Suggested Feature Flags

These names are only placeholders, but the staged approach should use something
like them:

- `win-tty-contract`
- `win-terminal-wrapper`
- `win-status`
- `win-advanced-input`
- `win-locate-extended`

The important part is that each stage can be enabled and disabled separately.

## Verification Matrix

Each phase should be checked in at least these environments:

- Windows Terminal interactive TTY
- WezTerm interactive TTY
- redirected or piped non-TTY input

And each verification pass should check at least:

- single Enter behavior
- no extra prompt artifacts
- no double echo
- stable line endings
- stable ordinary output while the REPL is active
- `read-line` behavior when console input is involved
- status-line redraw safety when enabled
- reduced locate behavior when advanced input is disabled

## Recommended First Deliverables

The safest short-term targets are:

1. document the terminal contract
2. extract the existing Windows input/output behavior into an explicit wrapper
   without changing behavior
3. align `key` and `read-line` newline and echo semantics
4. make `status-line.fs` work in a reduced, opt-in Windows mode

The full upstream editor stack should be treated as a later goal, not the first
recovery milestone.
