# Windows Terminal Contract

This document defines the Phase 1 terminal contract for the Windows-native
Gforth work.  It describes what the Windows terminal wrapper must provide to
the Forth layers above it before richer interactive behavior is restored.

The contract is intentionally conservative.  It preserves the current
`kernel/saccept.fs` startup behavior while giving later phases a stable target
for `ekey.fs`, `history.fs`, `status-line.fs`, and `locate1.fs`.

## Scope

The contract covers the boundary between Windows input/output mechanisms and
the Gforth runtime/editor layers.

In scope:

- `key-ior` and `key?`
- `read-line`
- newline normalization
- echo ownership
- standard stream text/binary mode
- TTY vs non-TTY behavior
- ordinary output and cursor-control assumptions
- future resize and `ekey` integration points

Out of scope for this phase:

- enabling `history.fs` by default on Windows
- enabling the full `ekey.fs` editor stack by default on Windows
- enabling `status-line.fs` by default on Windows
- implementing broad arrow-key or paging-key editing
- making `locate1.fs` interactive scrolling depend on advanced input

Phase 5 starts the reduced locate boundary by installing fancy locate scrolling
only when `ekey` is available.  On Windows, that extended locate behavior is
also gated by `GFORTH_WIN_LOCATE_EXTENDED=1`.

## Current Boundary

The current Windows behavior is implemented across several places:

- `engine/main.c` sets `stdin`, `stdout`, and `stderr` to binary mode on
  Windows.
- `engine/io.c` prepares the terminal, reads keys, checks key availability,
  and suppresses paired `CRLF` or `LFCR` newline bytes.
- `engine/support.c` provides the `read-line` implementation and still has a
  separate Windows console line-input path based on `ReadConsoleA`.
- `compat/win32/src/win32_compat.c` maps a small `termios`-like surface to
  Windows console modes.
- `kernel/io.fs` exposes the Forth-side input and output method vectors.
- `kernel/saccept.fs` is the default Windows command-line input path.

Phase 2 should extract or rename the implicit Windows pieces into an explicit
wrapper without changing the externally visible behavior described here.

## Input Contract

### `key-ior`

On Windows, `key-ior` must return either:

- one logical input byte or event value
- a negative I/O result code for error or interrupt

For the current simple mode, printable input should be byte-oriented and should
not require the upstream `ekey.fs` stack.

The wrapper must preserve these rules:

- one physical Enter produces one logical newline event
- a `CRLF` pair is seen by higher layers as one logical newline
- an `LFCR` pair is seen by higher layers as one logical newline
- a lone `CR` remains a logical newline
- a lone `LF` remains a logical newline
- paired newline suppression applies before Forth editor code sees input

Current behavior may return `CR` or `LF` depending on the source path.  Later
phases may choose a canonical newline representation, but Phase 2 must not
change that behavior accidentally.

### `key?`

On Windows, `key?` must report whether a logical input event is available
without consuming it.

For console input, `key?` must account for both:

- wrapper-owned pending keys
- Windows console key availability

For stream input, `key?` must preserve existing non-blocking behavior and must
not break redirected or piped input.

### `read-line`

`read-line` must follow the same newline policy as `key-ior`:

- `CRLF` is one line ending
- `LFCR` is one line ending
- lone `CR` and lone `LF` terminate a line
- newline terminators are not copied into the caller's buffer

The current code has a separate Windows console path for `read-line`.  Phase 3
must decide whether to keep that path, remove it, or route it through the same
wrapper helpers as key input.  Until then, Phase 2 should not change its
externally visible behavior.

### Echo Ownership

Echo must have exactly one owner for each input mode.

Current simple-mode policy:

- interactive Windows console input is prepared so Gforth owns echo
- `kernel/saccept.fs` echoes accepted printable characters when its `echo`
  variable is on
- `kernel/saccept.fs` turns its own echo off when `stdin` is not a TTY

The wrapper must avoid enabling host echo and Forth echo at the same time for
the same interactive input path.

The piped-input banner/input-line display observed in Phase 0 is recorded as
current behavior, not as a desired final guarantee.  A later phase may decide
to clean it up, but wrapper extraction must not change it unintentionally.

## Output Contract

### Standard Stream Mode

On Windows, `stdin`, `stdout`, and `stderr` must remain in binary mode after
startup initialization.

Reason:

- Gforth already emits Windows newlines explicitly
- C runtime text-mode rewriting can turn `CRLF` into `CRCRLF`

The Phase 0 smoke check confirmed that:

- `s" line" type cr bye` emits `6C 69 6E 65 0D 0A`
- no extra `0D` appears in that smoke case

### `type`, `emit`, and `cr`

The Forth-side output methods must continue to provide normal byte output.

For current Windows simple mode:

- `cr` should produce a normal Windows line break
- ordinary output must not duplicate or corrupt line endings
- redirected output must not contain `CRCRLF`

### Cursor Control

Cursor-control words such as `at-xy`, `at-deltaxy`, save/restore cursor, and
erase-display are not enough by themselves to prove status-line safety.

Before `status-line.fs` is enabled by default on Windows, the wrapper or
editor boundary must define:

- whether ANSI/VT sequences are available
- whether the active terminal is known to preserve cursor state correctly
- whether redraw may happen while an input line is active
- how prompt/input ownership is restored after redraw

## State Contract

### Terminal Size

The higher layers need stable width and height information.

For Phase 1:

- `form`, `rows`, and `cols` are the public Forth-side size concepts
- `status-line.fs` must not rely on full `history.fs` just to obtain a usable
  `screenw`
- a reduced Windows status mode must have a fallback width source

Phase 4 starts this boundary by making `status-line.fs` use `status-screenw`.
When `history.fs` has already provided `screenw`, `status-screenw` maps to it.
Otherwise, it provides a reduced fallback used only by the status-line code.

### Resize

Resize support is a future advanced feature.

The contract target is:

- resize is eventually surfaced as `k-winch` or an equivalent event
- `key?` may report availability when a resize event is pending
- `ekey` may return `k-winch` when advanced input is enabled

Until this is implemented and verified, reduced Windows mode must not require
resize events for correctness.

## Code Map

Current startup and I/O path:

1. `engine/main.c`
   Initializes the runtime and sets standard streams to binary mode on
   Windows.

2. `startup.fs`
   Chooses `kernel/saccept.fs` on `os-type s" win32" str=`.

3. `kernel/saccept.fs`
   Provides the current simple command-line `accept` loop and controls Forth
   self-echo for this path.

4. `kernel/io.fs`
   Defines the Forth-side input and output method vectors, including
   `key-ior`, `key?`, `type`, `emit`, `cr`, and optional terminal methods.

5. `engine/io.c`
   Implements terminal preparation, `key_avail()`, `getkey()`, console key
   reading, and newline-pair suppression.  The Windows wrapper boundary starts
   with helpers such as `gforth_win32_console_key_available()`,
   `gforth_win32_read_console_logical_key()`, and the newline-pair suppression
   helpers.

6. `engine/support.c`
   Implements `read_line()` and the separate Windows console `ReadConsoleA`
   line path.  Windows `read-line` handling now follows the same newline-pair
   policy as key input for `CRLF` and `LFCR`.

7. `compat/win32/src/win32_compat.c`
   Provides the Windows compatibility implementation for parts of the POSIX
   terminal surface, including `tcgetattr()` and `tcsetattr()`.

## No-Change Rules For Wrapper Extraction

Phase 2 must preserve the Phase 0 baseline:

- `.\build\native\gforth.exe -e '1 2 + . cr bye'` prints `3`
- piped input continues to execute successfully
- simple `cr` output emits one `CRLF`, not `CRCRLF`
- interactive Enter is processed exactly once
- no extra empty `ok` appears after one Enter
- interactive input is not echoed twice
- `kernel/saccept.fs` remains the default Windows startup path
- `status-line.fs`, `history.fs`, and full `ekey.fs` remain disabled by default
  on Windows

If any of these change, the phase should stop and the change should be treated
as a behavior change, not a refactor.

## Open Decisions

These are intentionally deferred until after the wrapper boundary is explicit:

- whether Windows should keep shipping the current compact native image, add a
  separate advanced-interactive image, or add a runtime loader for the richer
  startup stack
- whether `windows-interactive-advanced.fs` should remain a top-level opt-in
  report file or grow into the runtime loader once the compact image can
  compile the required helper words safely
- whether the opt-in native build checks (`-CheckAdvancedInteractive` and
  `-ProbeAdvancedInteractive`) should eventually become CI or release gates
- what current Gforth image-builder should be used for
  `scripts/build-advanced-interactive-image.ps1`, because the installed 0.7.0
  bootstrap can save images but cannot load this repository's current
  `comp-i.fs`
- whether canonical logical newline should be `CR` or `LF`
- whether the visible piped input line should remain part of Windows behavior
- whether the `ReadConsoleA` `read-line` path should remain separate
- how to expose Windows console virtual-terminal capability to Forth
- whether advanced input should produce native `ekey` values directly or emit
  VT-style byte sequences for `ekey.fs` to parse
- how resize should be detected in Windows Terminal, WezTerm, and redirected
  environments
