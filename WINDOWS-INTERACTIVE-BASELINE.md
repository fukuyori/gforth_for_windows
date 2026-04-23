# Windows Interactive Baseline

This note records the Phase 0 baseline for the Windows interactive recovery
plan.  It describes the behavior that should remain stable while the Windows
terminal wrapper is defined and extracted.

Date recorded: 2026-04-23

Manual interactive checks confirmed: 2026-04-23

Tested executable:

- `build/native/gforth.exe`
- version: `gforth 0.7.9_20260415+fukuyori.2.1 amd64`

## Baseline Expectations

The current Windows-native startup path intentionally keeps the simple
`kernel/saccept.fs` input path as the default.  The baseline to preserve is:

- one logical Enter is processed once
- no extra empty `ok` is produced from one Enter
- terminal echo is not duplicated
- ordinary output does not produce `CRCRLF`
- piped and redirected input continue to work
- `status-line.fs`, `history.fs`, and the full `ekey.fs` editor stack are not
  enabled by default on Windows

## Automated Smoke Checks

These checks can be run from PowerShell in the repository root.

### Basic execution

Command:

```powershell
.\build\native\gforth.exe -e '1 2 + . cr bye'
```

Observed result:

- exit code: `0`
- output: `3`

### Piped input

Command:

```powershell
"1 2 + . cr bye" | .\build\native\gforth.exe
```

Observed result:

- exit code: `0`
- the command is interpreted successfully
- output includes the startup banner
- output includes the piped input line followed by the result `3`

The visible piped input line is recorded as current behavior, not as a desired
long-term contract.  Phase 1 should decide whether this belongs in the final
Windows terminal contract or should be treated as behavior to clean up later.

### Output newline bytes

Command checked through a redirected child process:

```powershell
.\build\native\gforth.exe -e 's" line" type cr bye'
```

Observed result:

- exit code: `0`
- stdout bytes: `6C 69 6E 65 0D 0A`
- interpretation: `line` followed by a single `CRLF`

This confirms the current binary-mode output path is avoiding `CRCRLF` for this
smoke case.

## Manual Interactive Checklist

These checks require an actual interactive terminal and should be repeated in
both Windows Terminal and WezTerm.

Start:

```powershell
.\build\native\gforth.exe
```

Then verify:

- pressing Enter once produces one logical newline
- pressing Enter once does not produce an extra empty `ok`
- typed characters are not echoed twice
- Backspace removes one character visually and logically
- `1 2 + . cr` prints `3` once and returns to a clean prompt
- ordinary `cr` output uses normal line breaks
- exiting with `bye` restores the terminal to a usable state

## Non-TTY Checklist

These checks should be repeated after each low-level input/output change.

- piped input containing `LF` line endings still runs
- piped input containing `CRLF` line endings still runs
- redirected file input still runs
- command-line `-e` execution still emits stable `CRLF`
- output redirected to a file does not contain `CRCRLF`

## Phase 0 Status

Completed in this baseline:

- basic `-e` execution smoke test
- piped input smoke test
- output newline byte check for a simple `cr`

Confirmed manually:

- Windows Terminal interactive TTY behavior
- WezTerm interactive TTY behavior
- direct checks for single Enter, no extra `ok`, and no double echo

The Windows terminal contract is recorded in
`WINDOWS-TERMINAL-CONTRACT.md`.  The next implementation phase should extract
the wrapper boundary without changing the current default startup path.

## Phase 2 Recheck

Date rechecked: 2026-04-23

After extracting the first `engine/io.c` Windows wrapper helpers, the Phase 0
smoke checks were repeated.

Confirmed:

- `.\build\native\gforth.exe -e '1 2 + . cr bye'` exits with `0` and prints
  `3`
- piped input still executes successfully and prints `3`
- `s" line" type cr bye` still emits `6C 69 6E 65 0D 0A`
- byte-specified `CRLF` piped input executes successfully and prints `3`
- byte-specified `LFCR` piped input executes successfully and prints `3`
- interactive Windows terminal behavior was manually rechecked with no
  observed regression for single Enter, no extra `ok`, no double echo,
  Backspace, normal `cr` output, and terminal restoration after `bye`

Build note:

- building inside the sandbox failed when the bootstrap Gforth could not create
  a signal pipe
- the same native build succeeded when run outside the sandbox with approval

## Phase 3 Recheck

Date rechecked: 2026-04-23

After aligning Windows `read-line` newline-pair handling with the key-input
contract, the smoke checks were repeated.

Confirmed:

- native build completed successfully after retrying a transient
  `kernel/prim.fs` file lock
- `.\build\native\gforth.exe -e '1 2 + . cr bye'` exits with `0` and prints
  `3`
- piped input still executes successfully and prints `3`
- `s" line" type cr bye` still emits `6C 69 6E 65 0D 0A`
- `read-line` reads two `LF`-terminated input lines as length `3`, flag true
- `read-line` reads two `CR`-terminated input lines as length `3`, flag true
- `read-line` reads two `CRLF`-terminated input lines as length `3`, flag true
- `read-line` reads two `LFCR`-terminated input lines as length `3`, flag true

Confirmed manually:

- interactive Windows Terminal and WezTerm behavior was spot-checked again
  after the `read-line` alignment
- no regression was observed for single Enter, no extra `ok`, no double echo,
  Backspace, normal `cr` output, or terminal restoration after `bye`

## Phase 4 Recheck

Date rechecked: 2026-04-23

After adding the first reduced status-line compatibility boundary, the smoke
checks were repeated.

Confirmed:

- native build completed successfully
- `.\build\native\gforth.exe -e '1 2 + . cr bye'` exits with `0` and prints
  `3`
- piped input still executes successfully and prints `3`
- `s" line" type cr bye` still emits `6C 69 6E 65 0D 0A`
- piped `bye` startup and shutdown still complete successfully

Status-line scope:

- `status-line.fs` now uses `status-screenw`, which maps to `screenw` when
  `history.fs` has provided it and otherwise provides a reduced fallback
- Windows status-line auto-enable is gated by `GFORTH_WIN_STATUS=1` and
  terminal color capability
- the default Windows startup path remains `kernel/saccept.fs`

Confirmed manually:

- interactive Windows Terminal and WezTerm behavior was spot-checked again
  after the status-line compatibility change
- no regression was observed for single Enter, no extra `ok`, no double echo,
  Backspace, normal `cr` output, or terminal restoration after `bye`
- explicit `GFORTH_WIN_STATUS=1` opt-in startup was checked with no observed
  problem

## Phase 5 Recheck

Date rechecked: 2026-04-23

After gating `locate1.fs` fancy scrolling behind `ekey` availability and a
Windows opt-in flag, the smoke checks were repeated.

Confirmed:

- native build completed successfully
- `.\build\native\gforth.exe -e '1 2 + . cr bye'` exits with `0` and prints
  `3`
- piped input still executes successfully and prints `3`
- `s" line" type cr bye` still emits `6C 69 6E 65 0D 0A`

Locate scope:

- `locate1.fs` now only defines and installs `fancy-after-l` when `ekey` is
  available
- on Windows, extended locate scrolling additionally requires
  `GFORTH_WIN_LOCATE_EXTENDED=1`
- without that opt-in, Windows keeps the reduced locate mode and leaves
  `after-l` as the simple no-op default

Still manual:

- interactive Windows Terminal and WezTerm behavior should be spot-checked
  again because this phase touches startup-facing locate behavior
- when locate words are available in an interactive startup context, a simple
  `locate +` or equivalent should display source without entering fancy
  `ekey` scrolling by default

Manual note:

- `locate +` currently reports an undefined-word style error in the Windows
  native interactive image, so Phase 5 could not verify reduced locate display
  behavior directly
- this result means the current image is not entering fancy `ekey` locate
  scrolling by default, but restoring or exposing `locate` itself is a separate
  follow-up item

## Phase 6 Readiness Check

Date checked: 2026-04-23

Phase 6 is intended to restore richer editor behavior selectively.  Before
enabling any advanced editor feature, the current Windows native image was
checked for the words and source files that the advanced stack depends on.

Observed in the current native image:

- `locate` is not present
- `ekey` is not present
- `history-cold` is not present
- `see` is not present
- `require` and `included` are present
- `os-type` is not present

Runtime `require` checks:

- `require ekey.fs` currently fails on a dependency used by `ekey.fs`
- `require history.fs` currently fails on a dependency used by `user-object.fs`
- `require locate1.fs` currently fails while loading `status-line.fs`
- `require see.fs` currently fails on a dependency used by `float.fs`
- `require status-line.fs` currently fails outside the normal startup/build
  context

Conclusion:

- it is not yet safe to restore `history.fs`, `ekey.fs`, or richer locate
  behavior directly in the Windows native image
- Phase 6 should first address image/startup composition or provide an explicit
  advanced-interactive image/loading path
- the current `kernel/saccept.fs` default should remain unchanged until that
  composition issue is solved

Readiness helper:

- `scripts/check-advanced-interactive-readiness.ps1` records these checks in a
  repeatable form
- the helper currently passes the basic `-e` smoke check and confirms that
  `require` and `included` are available
- it currently reports missing advanced words such as `os-type`, `ekey`,
  `history-cold`, `locate`, `see`, and `+status`
- it currently reports failing runtime `require` checks for `ekey.fs`,
  `history.fs`, `status-line.fs`, `locate1.fs`, and `see.fs`

Advanced image probe:

- `scripts/build-advanced-interactive-image.ps1 -ProbeOnly` checks whether an
  advanced-interactive image can be built
- the current native image passes the basic smoke check but does not provide
  `savesystem` or `comp-image`
- the installed bootstrap Gforth can run and provides `savesystem` when run
  outside the sandbox
- the installed bootstrap Gforth is too old to load the current repository's
  `comp-i.fs`, so it cannot currently produce the advanced image
- until a current image-builder path exists, the script refuses to create
  `build/native/gforth-advanced.fi`

Native build integration:

- `scripts/build-native.ps1 -CheckAdvancedInteractive` runs the repeatable
  readiness checks after a native build
- `scripts/build-native.ps1 -ProbeAdvancedInteractive` runs the advanced image
  probe after a native build
- both switches are opt-in and leave the default simple Windows startup path
  unchanged

Observed result:

- `scripts/build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe" -CheckAdvancedInteractive -ProbeAdvancedInteractive`
  exits successfully
- the readiness section still reports the expected missing advanced words and
  failing runtime `require` checks
- the image probe still reports that the native image lacks `savesystem` and
  `comp-image`, and that the installed bootstrap Gforth cannot load the current
  `comp-i.fs`
- the readiness section now passes `require:windows-interactive-advanced.fs`
  and `advanced-loader:opt-in-report`
- this confirms the opt-in build checks are reporting Phase 6 blockers without
  changing the default Windows startup image

Runtime-loader entrypoint:

- `windows-interactive-advanced.fs` now provides a conservative opt-in
  entrypoint for the runtime-loader direction
- with `GFORTH_WIN_ADVANCED` unset, it loads silently and does not change the
  default simple Windows startup behavior
- with `GFORTH_WIN_ADVANCED=1`, it loads the reduced-safe `status-line.fs` and
  `locate1.fs` files before reporting readiness
- with `GFORTH_WIN_ADVANCED=1`, it reports `+status` as present while `ekey`,
  `history-cold`, `locate`, and `see` remain missing
- with `GFORTH_WIN_ADVANCED_QUIET=1`, it suppresses the human-readable report
  so scripts can check post-loader words directly
- the readiness helper now checks post-loader word state and confirms that
  `+status` becomes present while `locate`, `ekey`, and `history-cold` remain
  absent
- the file intentionally stays as top-level checks for now, because compiling
  generic helper words for these checks is not stable in the current compact
  image

## Phase 6A Blocker Classification

Date checked: 2026-04-23

`scripts/classify-advanced-interactive-blockers.ps1` classifies the current
advanced-interactive blockers and repeats checks so unstable compact-image
failures are visible instead of being mistaken for a single deterministic
missing word.

Observed with `-RepeatCount 3`:

- `os-type`, `ekey`, `history-cold`, `locate`, `see`, `+status`,
  `savesystem`, and `comp-image` are missing words in the current compact
  native image
- `windows-interactive-advanced.fs` passes repeated `require` checks
- `status-line.fs` and `locate1.fs` initially stopped on `[DO]`, which is a
  startup/build-context dependency
- `ekey.fs` can stop on `{` or on compact-image compile limitations, so it
  should not be loaded directly in the current compact image
- `history.fs` can stop on `nocov[` or on compact-image compile limitations
  inside `user-object.fs`
- `see.fs` can stop on `to-table:` or on compact-image compile limitations
  in its dependencies
- after replacing the `status-line.fs` compile-time `[DO]` color-table loop
  with explicit entries, `status-line.fs` can progress further and now exposes
  reduced-mode dependencies such as cursor save/restore, `base-execute`, and
  `f.s-precision`
- after adding reduced-mode gates for the status redraw implementation and
  wrapping full `locate1.fs` behavior behind `set-located-view`,
  `require status-line.fs` and `require locate1.fs` pass repeatedly in the
  compact native image
- `locate` itself is still not present in the compact image, because the full
  locate implementation depends on startup words such as `set-located-view`
- `windows-interactive-advanced.fs` now uses the safe reduced path by requiring
  `status-line.fs` and `locate1.fs` when `GFORTH_WIN_ADVANCED=1`
- attempts to add a reduced `locate` word at runtime were not stable in the
  compact image; the reduced path therefore only makes `locate1.fs` safe to
  load and leaves the `locate` word absent until a fuller startup context is
  available

Conclusion:

- the next useful implementation target is not direct `require` of the full
  advanced stack
- reduced features must either avoid these files, isolate very small subsets,
  or move to a fuller advanced image/loading path
- `status-line.fs` should continue to avoid startup-only words in reduced mode,
  and direct loading it is now safe in the current compact image
- `windows-interactive-advanced.fs` remains the safe opt-in entrypoint while
  the blocker categories are worked down

## Phase 6B Reduced History Persistence

Date checked: 2026-04-23

`scripts/probe-saccept-history-persistence.ps1` checks whether the current
compact Windows-native image can support a reduced history-persistence layer
without loading full `history.fs`.

Observed result:

- required primitives are present: `create-file`, `open-file`, `write-line`,
  `close-file`, `file-size`, `reposition-file`, `accept`, and `getenv`
- one-shot create/write/close with a constant file id passes
- `GFORTH_WIN_HISTORY=1` can be read before writing, so an opt-in gate is
  available
- an existing file can be opened and appended to with `file-size` and
  `reposition-file`
- the built native `accept` persists accepted lines when `GFORTH_WIN_HISTORY=1`
  and `GFORTH_WIN_HISTORY_FILE` points at a history file
- the default REPL path persists input lines through the same opt-in mechanism
- direct `require history.fs` still fails on startup-context or compact-image
  compile limitations, so the full upstream history stack remains disabled

Conclusion:

- reduced history persistence is now implemented as a small opt-in path
- `kernel/accept.fs`, `kernel/saccept.fs`, and `kernel-ec/saccept.fs` all keep
  the default no-history behavior unless `GFORTH_WIN_HISTORY=1` is set
- `GFORTH_WIN_HISTORY_FILE` selects the target file; without it, the reduced
  path uses `.gforth-history`
- this phase only persists lines; it does not provide history navigation,
  search, or full `history.fs` editor behavior

## Phase 6C Limited History Navigation

Date checked: 2026-04-23

Reduced history navigation is now available as a separate opt-in layer.  It is
intentionally smaller than full `history.fs` and does not require `ekey.fs`.

Observed result:

- `GFORTH_WIN_HISTORY_NAV=1` enables the reduced navigation handler
- `GFORTH_WIN_HISTORY_FILE` selects the history file to read
- `Ctrl-P` on an empty input line recalls the last line from the history file
- the recalled line is inserted into the normal input buffer and can be
  executed by pressing Enter
- `scripts/probe-saccept-history-persistence.ps1` now verifies this path with
  `runtime-nav:ctrl-p-last-line`
- a test history line `7 8 + .` recalled with `Ctrl-P` executes and prints
  `15`

Current scope:

- only previous-line recall is implemented
- recall is limited to an empty input line to avoid partial-line redraw risk
- Up/Down arrow escape-sequence handling is still deferred until selected
  `ekey` support is introduced
- full `history.fs` remains disabled in the compact Windows-native image

## Phase 6D Selected `ekey` Escape Sequences

Date checked: 2026-04-23

Selected ANSI escape-sequence handling is now available as an opt-in layer.
This does not load full `ekey.fs`; it only recognizes a small set of sequences
inside the existing compact `accept` path.

Observed result:

- `GFORTH_WIN_EKEY=1` enables the selected escape-sequence dispatcher
- `ESC [ A` maps to the same previous-line recall as `Ctrl-P`
- with `GFORTH_WIN_HISTORY_NAV=1`, ANSI Up recalls the last history line and
  the recalled line executes after Enter
- `ESC [ B`, `ESC [ 5 ~`, and `ESC [ 6 ~` are consumed safely instead of being
  inserted as literal text
- `scripts/probe-saccept-history-persistence.ps1` now verifies:
  `runtime-ekey:up-history`, `runtime-ekey:down-swallowed`,
  `runtime-ekey:page-up-swallowed`, and `runtime-ekey:page-down-swallowed`

Current scope:

- only ANSI Up performs an action
- Down, PageUp, and PageDown are safe no-op placeholders with a bell
- the dispatcher intentionally blocks while reading the rest of an escape
  sequence, but only when `GFORTH_WIN_EKEY=1` is set
- full `ekey.fs` and richer cursor navigation remain future work

## Phase 6E Compact `k-winch` Resize Marker

Date checked: 2026-04-23

The compact Windows-native image now exposes a reduced `k-winch` marker without
requiring full `ekey.fs`.  This lets the simple editor path consume pending
resize notifications without inserting control bytes into the input buffer.

Observed result:

- `k-winch`, `winch?`, and `form` are present in the compact native image
- `k-winch` uses the upstream-compatible compact value `0x80000017`
- `GFORTH_WIN_WINCH=1` enables the compact resize-event wrapper around
  `edit-key`
- when `winch?` is pending, `win-edit-key` surfaces `k-winch` to `decode`
- `decode` handles `k-winch` by refreshing `form` and continuing the current
  input line without inserting text
- `scripts/probe-saccept-history-persistence.ps1` verifies this with
  `runtime-winch:pending-flag-consumed`
- `scripts/check-advanced-interactive-readiness.ps1` now reports `k-winch`,
  `winch?`, and `form` as present
- `scripts/classify-advanced-interactive-blockers.ps1` reports `k-winch`,
  `winch?`, and `form` as ready

Current scope:

- the wrapper only consumes an already-pending `winch?` flag
- Windows console resize signaling still depends on the lower-level
  compatibility layer surfacing that pending flag
- this phase does not provide full `ekey.fs` event parity

## Phase 6F Integrated Opt-In Flag

Date checked: 2026-04-23

The reduced Windows interactive features can now be enabled either
individually or together with one integration flag.

Observed result:

- `GFORTH_WIN_INTERACTIVE=1` enables the reduced feature group
- the integration flag enables history persistence, history recall, selected
  ANSI escape-sequence handling, and compact `k-winch` handling
- the existing individual flags still work:
  `GFORTH_WIN_HISTORY`, `GFORTH_WIN_HISTORY_NAV`, `GFORTH_WIN_EKEY`, and
  `GFORTH_WIN_WINCH`
- `GFORTH_WIN_HISTORY_FILE` remains the shared history file selector
- `scripts/probe-saccept-history-persistence.ps1` verifies the integration
  path with `runtime-integrated:all-flags`
- with only `GFORTH_WIN_INTERACTIVE=1` and `GFORTH_WIN_HISTORY_FILE` set, ANSI
  Up recalls the last history line, the recalled line executes, the accepted
  line is persisted, and a pending `winch?` flag is consumed

Current scope:

- this is still an opt-in reduced mode, not the default Windows startup
- full `history.fs`, full `ekey.fs`, `see.fs`, and base `locate` remain outside
  the compact image path
- the integration flag is intended as the main manual-testing switch for the
  reduced Windows interactive stack

## Phase 6G Release Check Entry Point

Date checked: 2026-04-23

The reduced Windows interactive checks now have a single release-facing script.

Observed result:

- `scripts/check-windows-interactive-release.ps1` runs the reduced interactive
  probe, advanced readiness check, and blocker classification in sequence
- `-Build` can be used to rebuild the native image first
- `-ManualChecklistOnly` prints the Windows Terminal and WezTerm manual
  checklist without running automated checks
- the manual checklist uses `GFORTH_WIN_INTERACTIVE=1` and
  `GFORTH_WIN_HISTORY_FILE=.gforth-history`
- the checklist covers normal arithmetic input, Backspace, `bye`, ANSI Up
  recall, Down/PageUp/PageDown safe consumption, and resize-at-prompt behavior

Current scope:

- the release check records expected known blockers for full `history.fs`,
  `ekey.fs`, `see.fs`, and base `locate`
- manual terminal checks are still required before treating the reduced
  interactive stack as release-ready

## Phase 6H Reduced Interactive Probe Alias

Date checked: 2026-04-23

The reduced interactive probe now has a broader, release-oriented entrypoint.

Observed result:

- `scripts/probe-reduced-interactive.ps1` delegates to the existing
  `scripts/probe-saccept-history-persistence.ps1` implementation
- the probe output now reports itself as `reduced interactive probe`
- `scripts/check-windows-interactive-release.ps1` uses the broader probe name
  while the old script remains available for compatibility
- `WINDOWS-NATIVE.md` and `WINDOWS-INTERACTIVE-PLAN.md` now recommend the
  broader probe name for the reduced interactive stack

Current scope:

- this is a naming and release-flow cleanup only
- it does not change the native executable behavior

## Phase 6I Build Script Release Check Switch

Date checked: 2026-04-23

The native build entrypoint can now run the reduced Windows interactive release
checks after a successful build.

Observed result:

- `scripts/build-native.ps1` accepts `-CheckWindowsInteractiveRelease`
- the new switch calls `scripts/check-windows-interactive-release.ps1` against
  `build/native/gforth.exe`
- the switch is ignored for `-SyntaxOnly`, matching the other optional
  post-build checks

Current scope:

- this is an opt-in post-build check only
- it does not replace the standalone `scripts/check-windows-interactive-release.ps1`
  entrypoint

## Phase 6J Reduced Multi-Entry History Navigation

Date checked: 2026-04-23

Reduced history navigation now supports a small multi-entry path without
loading full `history.fs`.

Observed result:

- repeated ANSI Up walks from the newest history entry toward older entries
- ANSI Down walks back toward newer entries
- ANSI Down after a single Up clears back to an empty edit line
- `Ctrl-P` still recalls history through the same reduced path
- the release checklist now asks for repeated Up and Down manual coverage

Current scope:

- navigation is still opt-in through `GFORTH_WIN_HISTORY_NAV=1`,
  `GFORTH_WIN_EKEY=1`, or the integrated `GFORTH_WIN_INTERACTIVE=1`
- this is a compact reduced implementation, not full upstream `history.fs`

## Phase 6K Windows Console Extended-Key Translation

Date checked: 2026-04-23

Manual testing showed that Up, Down, PageUp, and PageDown did not trigger the
reduced ANSI escape handling in a real Windows terminal.

Observed cause:

- the automated probes feed ANSI escape bytes through stdin and therefore
  exercise `ESC [ A`, `ESC [ B`, `ESC [ 5 ~`, and `ESC [ 6 ~`
- real Windows console input reaches the native engine through `_getch()`
- `_getch()` reports these keys as an extended-key prefix followed by a scan
  code, not as ANSI bytes
- the native engine previously discarded the prefix and returned only the scan
  code, so `kernel/accept.fs` never saw the expected ESC sequence

Implemented result:

- `engine/io.c` now reads Windows console input with `ReadConsoleInputW` and
  translates extended keys into the same ANSI byte sequences used by the
  reduced Forth-side dispatcher
- Up maps to `ESC [ A`
- Down maps to `ESC [ B`
- PageUp maps to `ESC [ 5 ~`
- PageDown maps to `ESC [ 6 ~`
- the existing reduced interactive release checks still pass after rebuilding

Current scope:

- this covers the four keys currently handled by the reduced interactive mode
- other extended keys are not yet mapped
- real Windows Terminal / WezTerm manual confirmation is still required because
  the automated probes cannot press `_getch()` console keys directly

Follow-up adjustment:

- `GFORTH_WIN_EKEY=1` now also enables reduced history navigation reads
- this matches the user-facing expectation that opt-in Up/Down ekey handling
  can recall an existing reduced history file
- a later manual check showed that `_getch()` did not return arrow keys in the
  target terminal even though normal characters worked, so the engine now uses
  `ReadConsoleInputW` before falling back to `_getch()`
- a subsequent manual key-code probe confirmed that enabling VT input mode
  makes real keys arrive as expected:
- `a` produced `97`
- Up produced `27 91 65`
- Down produced `27 91 66`
- PageUp produced `27 91 53 126`
- PageDown produced `27 91 54 126`
- after seeding `.gforth-history` with `1 2 + .`, `GFORTH_WIN_INTERACTIVE=1`
  recalled the line with Up in a real terminal and executed it successfully
- the key-code probe default count was raised to `15` so the suggested
  `a`, Up, Down, PageUp, PageDown sequence is consumed completely and does not
  leave trailing escape bytes such as `5~` in the parent shell

## Phase 6L Reduced History Navigation Boundaries

Date checked: 2026-04-23

Reduced history navigation now has explicit boundary coverage.

Observed result:

- Up against an empty reduced-history file is consumed safely
- initial Up does not overwrite a user-typed line before history browsing
  starts
- repeated Up still walks to older history entries
- Down still walks back toward newer entries or an empty line
- the manual release checklist now asks for the typed-line preservation case

Current scope:

- this remains a compact reduced implementation
- full upstream `history.fs` behavior is still intentionally out of scope

## Phase 6M Runtime Artifact Ignore Hygiene

Date checked: 2026-04-23

Runtime and probe-generated files are now excluded from normal git status.

Observed result:

- `.gitignore` ignores `.gforth-history`
- `.gitignore` ignores `.tmp-history-*.txt`
- `.gitignore` ignores the older targeted probe names
  `.tmp-ekey-history.txt`, `.tmp-nav-history.txt`, and `.tmp-debug-history.txt`
- the reduced interactive probe still passes with the ignore rules in place

Current scope:

- this only affects working-tree hygiene
- it does not change runtime behavior
