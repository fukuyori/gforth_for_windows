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

### Phase 6: Stabilize the reduced interactive opt-in path

Only after the terminal contract, wrapper, and status-line integration are
stable should larger parts of the upstream editor stack be considered.  The
current `fukuyori.2.2` state has completed the reduced opt-in path, but the
full upstream stack is still intentionally absent from the compact Windows
image.

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

This order keeps the riskiest integration work last.  Items 1 through 10 are
the reduced interactive release path; the next phase starts the separate
advanced image/startup work needed for full upstream editor restoration.

### Phase 7: Restore the advanced image and startup foundation

Do not start Phase 7 by requiring `ekey.fs`, `history.fs`, `see.fs`, or the
full locate stack directly from the compact image.  Current probes show that
the compact Windows image does not expose image-building or full startup words
such as `savesystem`, `comp-image`, `os-type`, `ekey`, `history-cold`, `see`,
or `locate`.  Direct `require` attempts also fail on missing startup context
or compact-image compile limitations:

- `ekey.fs` currently fails on locals syntax such as `{ ... }`
- `history.fs` currently fails through `user-object.fs` on `nocov[`
- `see.fs` currently fails through `stuff.fs`
- `locate1.fs` is safe to require, but the base `locate` word is absent until
  the full locate startup context is available
- `vt100.fs` and `ansi.fs` are not enough to enable a real status bar until
  their startup dependencies, including `base-execute` and cursor-control
  words, are available

The first Phase 7 task is therefore to make a safe advanced image or advanced
startup path real.

Deliverables:

- decide whether Windows ships a separate `gforth-advanced.fi`, an advanced
  startup loader, or both
- make `scripts/build-advanced-interactive-image.ps1` move beyond probe-only
  status once the image layout is validated
- account for the current default native image origin: `build/native/gforth.fi`
  is copied from the cross-built `kernl64l.fi` compact image, so it is not
  expected to contain the full `startup.fs` or image-builder word surface
- provide or bootstrap an image builder that has `savesystem` and `comp-image`
  for the current source tree
- resolve the current bootstrap mismatch where the installed bootstrap Gforth
  can run but cannot load this tree's `comp-i.fs` because of missing words such
  as `$Variable`
- distinguish the two current partial builder surfaces: the native compact
  image has `current-section`, `section-dp`, and `$Variable` but lacks
  `savesystem`, `comp-image`, `MEM+DO`, locals, `nocov[`, and `base-execute`,
  while the installed `gforth 0.7.0` bootstrap has `savesystem`, `dump-fi`,
  `{`, and `base-execute` but lacks `current-section`, `section-dp`,
  `$Variable`, `MEM+DO`, `{:`, and `nocov[`
- treat the native compact image as a runtime kernel, not a full startup
  construction base: minimal colon compilation can work, but direct `require`
  and `startup.fs` layering still fail on missing startup/build dependencies
- account for the partial environment/search-order surface explicitly:
  `search-wordlist` and `get-current` are present, but `vocabulary`,
  `wordlist`, `set-current`, `get-order`, and `set-order` are not; a small
  `environment-wordlist`/`set-current` shim can sometimes make isolated
  `envos.fs` report `os-type=win32`, but it is invocation-context sensitive
  and is not a substitute for the full `environ.fs`/startup environment
- treat direct prerequisite loading as a diagnosed dead end until proven
  otherwise: the compact image currently fails early on `to.fs`, `environ.fs`,
  `float.fs`, `glocals.fs`, and `debugs.fs`, and the bootstrap moves from
  `$Variable` to `section-dp` even with a simple `$Variable` shim
- treat direct full-startup invocation on the compact image as unavailable
  until the startup context is repaired: unshimmed `envos.fs` stops at
  `environment-wordlist`, the minimal shim is diagnostic-only and can still
  fail at `;`, and `exboot.fs startup.fs` does not reach `savesystem` even
  when invoked with `--clear-dictionary --no-offset-im`
- use the startup-prefix probes as the next repair guide: `rec-sequence.fs`
  can load, but `except.fs` stops at `first-throw on ;`, and the
  `rec-sequence.fs` plus `search.fs`/`options.fs`/`environ.fs`/`envos.fs`
  prefix still stops at compact-image compile-context `;` blockers before the
  later editor and image-builder files are reached
- refine that repair guide with the current compile-context split:
  ordinary literals and primitive compilation can corrupt the colon-sys before
  recognizer setup, while controlled probes after `rec-sequence.fs` can compile
  `: plus + ;`, `: one 1 ;`, and the core `naligned` body; this makes
  recognizer/compiler initialization the first concrete Phase 7 repair target
- treat `rec-sequence.fs exboot.fs startup.fs` as a diagnostic candidate, not a
  committed startup change yet: it can move the visible blocker from `;` to
  `os-type`, so the next boundary after recognizer initialization is making
  `os-type` and the environment wordlist visible at the first Windows branch
  in `startup.fs`
- treat the standard `gforthmi` fixed-image stage as blocked on Windows native
  for now: both the `--no-offset-im` and `--offset-image` saves stop before
  producing the two temporary images, with current visible blockers in early
  environment/startup setup such as `os-type`/`;` or the `except.fs`
  `first-throw on`/`;` path depending on invocation
- do not rely on existing local staged images as the advanced base: the
  current default image, `kernl64l.fi`, installer-stage image, and
  `.tmp-stagecheck` image all lack the advanced builder and full interactive
  surface
- treat simple cross-built builder-intermediate images as still blocked:
  `kernel/main.fs` alone can still be saved as the compact kernel image, but
  adding `savesys.fs` after `kernel/main.fs` segfaults before a builder image
  is produced, and adding a larger builder prefix also now segfaults after
  passing the former `U+DO` blocker
- current segmentation-fault boundary: after `kernel/main.fs`, `include to.fs`
  can still complete, but `require search.fs` or `include search.fs`
  segfaults before later `glocals.fs`, `stuff.fs`, or `savesys.fs` work can
  start
- pre-kernel loading is only partially viable: `search.fs` can be loaded before
  `kernel/main.fs`, but the full builder prefix is blocked immediately in
  `to.fs` because the installed `gforth 0.7.0` bootstrap lacks `value-to`
  and a one-word `value-to` shim only moves the blocker to `Create-from`
- next implementation step: stop appending full libraries after
  `kernel/main.fs`; instead decide between a newer/current preforth-style
  bootstrap, a small compatibility layer for the installed bootstrap, or a
  smaller target-safe post-kernel subset that avoids `search.fs`/`glocals.fs`
  until the full image-builder path exists
- for the native full-startup route, test changes in this order:
  recognizer/compiler initialization before `except.fs`, then
  environment/search-order visibility for `os-type`, then `savesystem`
  availability, then the advanced editor libraries
- current checkpoint: the normal `exboot.fs startup.fs` probe can now reach a
  visible `savesystem` after explicitly looking up `os-type` in the
  `environment` vocabulary, using `kernel/saccept.fs` for the Windows branch,
  and making status/rec-scope/obsolete compatibility hooks tolerate the
  absence of full `history.fs` and `ekey.fs`
- current advanced-image checkpoint: `scripts/build-advanced-interactive-image.ps1`
  can now move beyond `-ProbeOnly`, produce `build/native/gforth-advanced.fi`,
  and smoke-test it before accepting it
- the accepted advanced image exposes `savesystem`, `see`, `locate`, and
  `+status`; `comp-image` remains a build-stage word rather than an image
  surface word
- the Windows offset-image stage is still not fully relocatable: the build can
  warn that the two images have the same base address, and the script keeps a
  two-no-offset data-relocatable fallback only if the resulting image starts
  cleanly
- next implementation step: start Phase 8 against
  `build/native/gforth-advanced.fi` by isolating the full `ekey.fs` `;`
  failure; do not move that work into the default compact image
- in parallel, isolate why `exboot.fs`/`startup.fs` stops before
  `savesystem` on the native compact kernel, first separating the generic
  compact-image `;` compile-context blocker from missing environment/search-
  order words and the later exception-frame `first-throw` path; resolving that
  would reopen the normal `gforthmi` path for producing `gforth-advanced.fi`
- keep `build/native/gforth.fi` on the stable `kernel/saccept.fs` startup path
  while the advanced path is developed

Verification:

- `scripts/build-advanced-interactive-image.ps1 -ProbeOnly` clearly reports
  the proposed image layout, confirms that the advanced image would stay
  separate from `build/native/gforth.fi`, and reports which image-builder
  prerequisites are available
- `scripts/build-advanced-interactive-image.ps1` without `-ProbeOnly` either
  builds and smoke-tests `build/native/gforth-advanced.fi` or fails before
  accepting a broken image
- `scripts/classify-advanced-interactive-blockers.ps1` remains repeatable
- `scripts/check-windows-interactive-release.ps1` continues to pass for the
  reduced path after every advanced-image change

### Phase 8: Restore full `ekey.fs`

Once Phase 7 provides a real advanced path, restore `ekey.fs` there first.  The
Windows console wrapper already translates the reduced set of real console
keys into ANSI byte sequences, and full `ekey.fs` is the layer that turns those
sequences into upstream-style key events.

Current checkpoint:

- `scripts/build-advanced-interactive-image.ps1 -IncludeEkey` now builds
  `build/native/gforth-advanced.fi` with full `ekey.fs` included
- the script accepts the image only after a smoke test and an `ekey` word
  check
- the current accepted advanced image exposes `ekey`, `k-left`, `k-f1`, and
  `k-winch`
- default `build/native/gforth.fi` still does not load full `ekey.fs`

Scope:

- keep default Windows startup on `kernel/saccept.fs`
- keep `ekey` present only in the advanced path at first
- preserve one-Enter, no-double-echo, and newline normalization behavior
- map any additional Windows console keys only after the core `ekey` path is
  stable
- surface resize as `k-winch` in a way compatible with full `ekey`

Completion criteria:

- `ekey` exists in the advanced path
- printable keys, Enter, Up, Down, PageUp, PageDown, and resize smoke checks
  pass
- reduced `GFORTH_WIN_INTERACTIVE=1` checks still pass

### Phase 9: Restore full `history.fs`

After `ekey.fs` is available, restore the full upstream line editor and history
stack in the advanced path.

Current checkpoint:

- `scripts/build-advanced-interactive-image.ps1 -IncludeHistory` now builds
  `build/native/gforth-advanced.fi` with full `ekey.fs` and full `history.fs`
  included
- the script accepts the image only after a smoke test plus `ekey` and
  `history-cold` word checks
- the current accepted advanced image exposes `history-cold`,
  `edit-terminal`, and `bindkey`
- `scripts/check-advanced-image-runtime.ps1` verifies the accepted advanced
  image surface and a non-interactive `history-cold` / `write-history` path
- the same runtime probe now verifies redirected-stdin REPL persistence into
  `GFORTHHIST`
- the runtime probe also verifies relative `GFORTHHIST` filenames such as
  `.gforth-advanced-history`; `history.fs` now creates parent directories only
  when the selected history path actually contains a parent slash
- redirected stdin does not verify full Up/Down navigation, because ANSI Up is
  observed as literal `A` outside a real terminal
- after manual testing showed key sequences appearing for arrows and
  PageUp/PageDown, the advanced image build now restores `kernel/accept.fs`
  before loading `ekey.fs` and `history.fs`, so the advanced REPL uses the
  full editor rather than the reduced `kernel/saccept.fs` input path
- native Windows input now maps Left, Right, Home, and End console events to
  ANSI sequences for full `ekey.fs`; Up, Down, PageUp, and PageDown remain
  covered by the existing mappings
- the reduced `GFORTH_WIN_INTERACTIVE=1` Up / Down / PageUp / PageDown work was
  already fixed in `fukuyori.2.2`; the current failures and fixes apply to the
  separate advanced image path with full `ekey.fs` / `history.fs`
- after manual testing showed Left, Right, and Backspace working while Up,
  Down, PageUp, and PageDown did not recall history, the remaining blocker was
  traced to relative `GFORTHHIST` being created as a directory instead of a
  file; this is now fixed in the advanced image
- the stale `.gforth-advanced-history` directory created by the earlier bug was
  removed; the manual test path is now a real history file
- full `ekey.fs` depends on side-effect-free `key?` while reading escape
  sequences; Windows console `key?` now peeks for available key events without
  queueing ANSI bytes into the pending-key buffer
- Windows console PageUp/PageDown events and VT raw input sequences are
  normalized to the same short history-navigation sequences as Up/Down in the
  advanced path, avoiding the observed `5~` / `6~` tail leakage while
  preserving the current `history.fs` behavior
- the final manual PageUp/PageDown blocker was the real Windows virtual-key
  path: `VK_PRIOR` / `VK_NEXT` were being consumed without reaching the full
  editor as history navigation
- `engine/io.c` now returns native Gforth ekey codes directly for Windows
  console cursor and paging keys, and `ekey.fs` no longer sends those keycodes
  through the extended-character reader
- `scripts/probe-advanced-page-keys-console.ps1` automates the advanced
  PageUp/PageDown check from a real interactive terminal by injecting console
  input and failing if `5~` / `6~` leaks into output
- the PageUp/PageDown probe now covers three paths: full `ESC [ 5 ~` /
  `ESC [ 6 ~` text, split CSI tail input, and real `VK_PRIOR` / `VK_NEXT`
  console key events
- `scripts/check-windows-interactive-release.ps1` now runs that advanced image
  runtime probe when `build/native/gforth-advanced.fi` exists
- manual retesting on 2026-04-24 confirmed that PageUp and PageDown recall and
  clear full-history entries in the advanced image
- default `build/native/gforth.fi` still does not load full `history.fs`

Important dependencies:

- `history.fs` owns editor state such as `screenw`, `edit-curpos`,
  `edit-update`, and the calls to `.status` and `.unstatus`
- echo ownership must remain single-owner; host echo and Forth redraw must not
  both act on the same input
- reduced history files and full history files need an explicit compatibility
  decision before sharing state

Completion criteria:

- `history-cold` is available in the advanced path
- non-interactive full-history file writing is verified in the advanced path
- interactive full history navigation is verified in the advanced path
- Backspace, cursor movement, redraw, and history recall work in Windows
  Terminal and WezTerm
- reduced history persistence and navigation remain unchanged outside the
  advanced path

Phase 9 handoff:

- full `history.fs` recovery is complete enough for the advanced path
- keep `scripts/probe-advanced-page-keys-console.ps1` in the release checklist
  so regressions in text escape sequences, split CSI tails, and real
  PageUp/PageDown virtual-key events are caught automatically
- proceed to Phase 10 for `see.fs` and full locate behavior checks

### Phase 10: Restore `see.fs` and full `locate`

With the full editor stack available, restore the tools that depend on the
full startup context.

For `see.fs`:

- resolve the `stuff.fs` and table/startup-context blockers in the advanced
  image
- verify `see` on representative colon definitions and primitives

For `locate`:

- keep `locate1.fs` safe to require in reduced mode
- make the base `locate` word available only when the full locate context is
  present
- enable fancy locate scrolling only when full `ekey` is available

Completion criteria:

- `see` and `locate` exist in the advanced path
- simple source navigation works without enabling the status bar
- fancy locate navigation works only in full advanced input mode

### Phase 11: Restore the status bar

The status bar should be the last advanced interactive feature to become
release-facing.  `status-line.fs` can be made safe to load in reduced modes,
but a visible, useful status bar depends on the full editor and terminal
redraw contract.

Requirements before visible status-bar enablement:

- `ansi.fs` and `vt100.fs` startup dependencies are available in the advanced
  path
- `save-cursor-position`, `restore-cursor-position`, and `erase-display` are
  real cursor-control words, not only noop fallbacks
- full `history.fs` redraw state is available
- `.status` and `.unstatus` do not corrupt the current input line
- resize updates width state before status redraw

Activation order:

1. keep `GFORTH_WIN_STATUS=1` as the explicit opt-in
2. allow status-bar testing only in the advanced path
3. verify coexistence with full history, `see`, `locate`, and resize handling
4. consider making the advanced status bar a supported opt-in
5. consider any default-on behavior only after multiple manual terminal
   verification passes

Completion criteria:

- the status bar displays in Windows Terminal and WezTerm under advanced opt-in
- normal input, history navigation, `see`, `locate`, and resize all remain
  usable while the status bar is enabled
- default Windows startup still works without the advanced path

## Safety Rules

The implementation should follow these rules.

- Keep the current `saccept.fs` startup path as the default until the new path
  is proven.
- Treat wrapper extraction as a no-behavior-change refactor first.
- Put richer behavior behind explicit feature flags or a Windows-specific
  startup toggle first.
- Treat advanced image/startup recovery as a prerequisite for full upstream
  `ekey.fs`, `history.fs`, `see.fs`, `locate`, and visible status-bar work.
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

## Recommended Next Deliverables

The Phase 0 through Phase 6 reduced-mode targets are complete enough to use as
the stable baseline.  The next short-term targets are:

1. keep the reduced release checks green
2. keep `scripts/build-advanced-interactive-image.ps1` producing and
   smoke-testing `build/native/gforth-advanced.fi`
3. keep full `ekey.fs` and full `history.fs` in the advanced image through
   `scripts/build-advanced-interactive-image.ps1 -IncludeHistory`
4. verify full-history runtime behavior in the advanced image
5. keep status-bar activation until after `ekey.fs`, `history.fs`, `see.fs`,
   and locate behavior are proven in the advanced image

The full upstream editor stack should remain an advanced-path goal until the
image builder, startup context, and status redraw contract are all proven.
