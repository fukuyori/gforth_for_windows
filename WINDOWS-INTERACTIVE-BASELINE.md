# Windows Interactive Baseline

This note records the Phase 0 baseline for the Windows interactive recovery
plan.  It describes the behavior that should remain stable while the Windows
terminal wrapper is defined and extracted.

Date recorded: 2026-04-23

Manual interactive checks confirmed: 2026-04-23

Tested executable:

- `build/native/gforth.exe`
- version: `gforth 0.7.9_20260415+fukuyori.2.0 amd64`

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
- with `GFORTH_WIN_ADVANCED=1`, it reports the currently missing advanced
  words: `ekey`, `history-cold`, `locate`, `see`, and `+status`
- the file intentionally stays as top-level checks for now, because compiling
  generic helper words for these checks is not stable in the current compact
  image
