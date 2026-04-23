# Windows Native Build Notes

This repository is a fork of
[forthy42/gforth](https://github.com/forthy42/gforth) that adds a native
Windows build, runtime fixes for interactive terminals, and an Inno Setup
installer flow.  The current fork release is based on `Gforth 0.7.9_20260415`
and is versioned as `0.7.9_20260415+fukuyori.2.1`.

The goal is to build and package `gforth.exe` on Windows without depending on
MSYS2 or MinGW at runtime.

## Goals

The Windows-native work has four practical goals:

- build `gforth.exe` with a native Windows toolchain
- keep the self-hosted bootstrap flow working on Windows
- make the interactive REPL behave correctly in Windows Terminal and WezTerm
- produce a per-user installer that ships only the files needed at runtime

The implementation keeps the existing Gforth tree mostly intact.  Instead of
replacing the Unix-oriented build, it adds a Windows compatibility layer,
PowerShell build scripts, and targeted runtime fixes.

## Build Entry Points

Native build:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe"
```

Native build with the Phase 6 advanced-interactive readiness checks:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe" -CheckAdvancedInteractive -ProbeAdvancedInteractive
```

Native build with the reduced Windows interactive release checks:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe" -CheckWindowsInteractiveRelease
```

These optional checks do not change the default Windows startup path.  They
report whether the current native image can see advanced interactive words such
as `ekey`, `history-cold`, `locate`, `see`, whether an advanced image build
path is currently available, and whether the reduced interactive release stack
still passes.

The temporary runtime-loader entrypoint is:

```powershell
$env:GFORTH_WIN_ADVANCED = "1"
.\build\native\gforth.exe .\windows-interactive-advanced.fs -e 'bye'
Remove-Item Env:\GFORTH_WIN_ADVANCED
```

At this stage it only reports readiness.  It does not activate the advanced
editor stack.  With `GFORTH_WIN_ADVANCED=1`, it also loads the reduced-safe
`status-line.fs` and `locate1.fs` paths before reporting.
Set `GFORTH_WIN_ADVANCED_QUIET=1` when a script needs to inspect post-loader
words without the human-readable readiness report.

To classify the current advanced-interactive blockers:

```powershell
.\scripts\classify-advanced-interactive-blockers.ps1 -RepeatCount 3
```

This reports whether failures are missing words, startup/build-context
dependencies, image-builder mismatches, or compact-image compile limitations.
In the current `fukuyori.2.1` follow-up state, `status-line.fs` and
`locate1.fs` are safe to `require` in the compact image, but the `locate` word
itself is still absent until the full locate startup context or an advanced
image is available.

Installer build from an existing native build:

```powershell
.\scripts\build-installer.ps1
```

If you explicitly want one command to run both stages:

```powershell
.\scripts\build-installer.ps1 -BuildNative -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe"
```

The native build produces:

- `build/native/gforth.exe`
- `build/native/gforth.fi`

The installer build produces:

- `build/installer/output/gforth-native-<version>-x64-setup.exe`

For the staged recovery plan for richer Windows interactive behavior, see
`WINDOWS-INTERACTIVE-PLAN.md`.

## Port Summary

### 1. Windows compatibility layer

The engine expects a Unix/POSIX environment and headers such as `unistd.h`,
`dirent.h`, `pwd.h`, `termios.h`, `sys/mman.h`, `sys/ioctl.h`,
`sys/resource.h`, and `sys/time.h`.  Windows does not provide these directly.

To bridge that gap, this fork adds a compatibility layer under:

- `compat/win32/include`
- `compat/win32/src/win32_compat.c`

This layer provides the minimum runtime surface needed by the engine, including:

- POSIX-like file and directory access
- `mmap`/`munmap` style helpers
- `gettimeofday` and `getrusage` equivalents
- `getpwuid` and `getpwnam` style account lookup
- terminal-related shims
- signal compatibility, including `SIGWINCH`

The template `compat/win32/native-config.h.in` also carries Windows-specific
build properties used by the native build.

### 2. Native build script

`scripts/build-native.ps1` is the native build entry point.  It replaces the
usual Unix `configure`/`make` path with a PowerShell-driven build that can run
on a normal Windows installation.

The script is responsible for:

- locating the bootstrap `gforth.exe`
- locating the bootstrap image when needed
- locating `m4.exe` when available
- generating primitive tables and kernel-generated files
- compiling the compatibility layer and engine objects
- linking `build/native/gforth.exe`
- copying the generated image to `build/native/gforth.fi`
- optionally running the Phase 6 advanced-interactive readiness and image
  probe checks when `-CheckAdvancedInteractive` or `-ProbeAdvancedInteractive`
  is specified
- optionally running the reduced Windows interactive release checks when
  `-CheckWindowsInteractiveRelease` is specified

The build is still partially self-hosted, so a working Gforth remains part of
the bootstrap path.

### 3. Image handling

The executable expects `gforth.fi` by default.  The native build now ensures
that the generated image is copied into that name, so this works directly:

```powershell
.\build\native\gforth.exe
```

On Windows, the image-loading path in `engine/main.c` also falls back to
`fread()` when file-backed mapping is not available.  That avoids startup
failures caused by incomplete image mapping assumptions.

## Interactive Console Fixes

The most visible runtime issues during the port were all around Enter handling
and terminal echo.

### Symptoms

Before the current fixes, interactive use on Windows could show problems such
as:

- one Enter being processed twice
- an extra empty `ok`
- line breaks appearing incorrectly in Windows Terminal or WezTerm
- input echo showing up in the wrong place

### What changed

The current implementation fixes those problems in three layers.

First, `engine/main.c` switches `stdin`, `stdout`, and `stderr` to binary mode
on `_WIN32`.  Gforth already emits Windows newlines explicitly, so this avoids
the C runtime rewriting `\n` again and turning a logical newline into
`CR CR LF`.

Second, `engine/io.c` now treats the Windows console as a key-by-key input
source under Gforth's control:

- `prep_terminal()` clears `ICANON` and `ECHO` for Windows TTY input
- `getkey()` normalizes `CRLF` and `LFCR` into a single logical newline
- the same newline normalization is also applied to non-TTY stream input

This keeps Enter as one logical action and makes the REPL handle Windows
terminal input consistently.

Third, `kernel/saccept.fs` uses the simple `accept` loop on Windows too, rather
than delegating to `read-line`.  For non-TTY input, it also disables Gforth's
self-echo so terminal emulators do not show a second copy of the typed line.

Together, these changes make the REPL behave as expected in both Windows
Terminal and WezTerm.

### Current interactive differences from upstream

The current Windows-native path intentionally favors predictable console
behavior over the full upstream interactive editing stack.

At startup, Windows uses `kernel/saccept.fs` instead of the usual
`ekey.fs` plus `history.fs` path.  In practice, that means the Windows-native
REPL currently uses a simpler character-by-character `accept` loop rather than
the richer upstream command-line editor.

Compared with the normal upstream startup path, the following areas are
currently reduced or missing on Windows-native builds:

- command history loading, saving, and navigation
- the higher-level command-line editing layer from `history.fs`
- VT100/ANSI escape sequence handling from `ekey.fs`
- arrow-key and other extended-key driven editing behaviors that depend on
  `ekey.fs`
- resize-driven terminal UI behavior that depends on `ekey` events such as
  `k-winch`

This is a deliberate tradeoff in the current port.  The simpler Windows input
path avoids the double-Enter, double-echo, and newline translation problems
that showed up when trying to use the upstream interactive stack unchanged in
Windows Terminal and WezTerm.

The status line is only partially disabled.  Windows-native startup does not
load `status-line.fs` directly, so the status bar is not part of the default
Windows startup experience.  However, the file is still present in the tree and
can still be pulled in indirectly by other source files such as `locate1.fs`.

### Restoration feasibility and rough effort

Based on the current Windows-native implementation, not all of the reduced
interactive features have the same restoration cost.

Lower-effort candidates:

- restoring `status-line.fs` as an optional or default startup feature
- small improvements inside `kernel/saccept.fs`
- making the status line opt-in on Windows while leaving the simpler input path
  in place

These are comparatively lightweight because `status-line.fs` still exists in
the tree and `kernel/saccept.fs` is intentionally simple.

Medium-effort candidates:

- restoring some history behavior without restoring the full upstream editor
- cleaning up the interaction between `locate1.fs` and `status-line.fs` on
  Windows
- restoring limited locate-time navigation with simple keys rather than the
  full `ekey` stack

These are more involved because the upstream locate and history experience is
partly coupled to the richer editor and key handling layers.

Higher-effort candidates:

- restoring the full upstream `history.fs` line editor on Windows-native builds
- restoring broad arrow-key, paging-key, and other extended-key behavior from
  `ekey.fs`
- restoring resize-driven interactive behavior that depends on `k-winch`

These are the expensive items because the current Windows-native port
deliberately replaced the upstream `ekey.fs` plus `history.fs` startup path
with the simpler `kernel/saccept.fs` path in order to avoid double-Enter,
double-echo, and newline translation problems.

As a rough planning guide:

- low effort: about half a day to two days
- medium effort: about one to four days
- high effort: about three to nine days, depending on how much upstream editor
  behavior needs to be restored and verified

In practice, the safest order is:

1. small `saccept.fs` improvements
2. optional or limited `status-line.fs` restoration
3. targeted history or locate improvements
4. only then, consider restoring larger parts of the `ekey.fs` and
   `history.fs` editing stack

The longer-term staged recovery plan has since been rewritten around a
Unix-like terminal contract for Windows.  See
`WINDOWS-INTERACTIVE-PLAN.md`.

### Output newline normalization

Terminal emulators that sit on top of ConPTY, such as WezTerm, were especially
sensitive to the old text-mode behavior.  With text-mode standard streams, each
`\n` byte in an existing `CRLF` pair could be rewritten again, producing
`CR CR LF`.

Keeping the standard streams in binary mode preserves Gforth's own newline
handling and makes terminal output land as plain `CRLF`.

## Installer and Distribution Layout

The Windows-native packaging flow is built around these files:

- `scripts/stage-native-dist.ps1`
- `scripts/build-installer.ps1`
- `installer/gforth-native.iss`

### Staging

`scripts/stage-native-dist.ps1` creates `build/installer/stage` from the native
build output.

The staged tree focuses on runtime content:

- `gforth.exe`
- `gforth.fi`
- root `.fs`, `.fb`, and `.4th` files
- selected top-level documentation files
- `compat`
- `kernel`
- `unix` files needed for runtime loading
- `wordlibs` runtime support files

Large development-oriented trees such as `arch`, `doc`, and `engine` are not
shipped in the installer stage.

### Inno Setup

`installer/gforth-native.iss` builds a per-user x64 installer.

Important installer choices:

- install location is `{localappdata}\Programs\Gforth`
- no administrator privileges are required
- PATH modification is optional and unchecked by default
- a desktop shortcut is optional and unchecked by default
- the installer can launch `gforth.exe` after installation

The installer consumes the staged tree recursively, so the staging step defines
the contents of the final package.

## Files Most Directly Involved

The core Windows-native work is concentrated in:

- `compat/win32/include/*`
- `compat/win32/src/win32_compat.c`
- `compat/win32/native-config.h.in`
- `engine/io.c`
- `engine/main.c`
- `kernel/saccept.fs`
- `scripts/build-native.ps1`
- `scripts/stage-native-dist.ps1`
- `scripts/build-installer.ps1`
- `installer/gforth-native.iss`

## Known Limitations

This fork establishes a native Windows build and packaging path, but it does
not claim that every Forth source file in the repository is fully validated in
the Windows-native configuration.

In particular:

- the build remains bootstrap-dependent on an existing Gforth
- some optional library-loading paths are still Unix-oriented
- the installer packaging focuses on runtime use, not a full development tree

The current target is a reliable native executable, a usable interactive REPL,
and a reproducible Windows installer flow.

## Verification Commands

Basic smoke test:

```powershell
.\build\native\gforth.exe -e '1 2 + . cr bye'
```

Reduced interactive probe:

```powershell
.\scripts\probe-reduced-interactive.ps1
```

The older `.\scripts\probe-saccept-history-persistence.ps1` name remains
available as a compatibility entrypoint.

Reduced interactive release check:

```powershell
.\scripts\check-windows-interactive-release.ps1
```

To include a native rebuild first:

```powershell
.\scripts\check-windows-interactive-release.ps1 -Build
```

Alternatively, request the same release checks from the native build entrypoint:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe" -CheckWindowsInteractiveRelease
```

To print only the manual Windows Terminal and WezTerm checklist:

```powershell
.\scripts\check-windows-interactive-release.ps1 -ManualChecklistOnly
```

To inspect how real console keys reach the native engine:

```powershell
.\scripts\show-win-key-codes.ps1
```

Press Up, Down, PageUp, and PageDown.  With the Windows console extended-key
translation active, Up should begin with `27 91 65`, Down with `27 91 66`,
PageUp with `27 91 53 126`, and PageDown with `27 91 54 126`.
If normal keys such as `a` print but the arrow keys do not, the console-input
translation layer is not receiving KEY_EVENT records in that terminal session.
The default probe count is `15`, enough to consume `a`, Up, Down, PageUp, and
PageDown without leaving trailing escape bytes in the parent shell.

Opt-in reduced history persistence:

```powershell
$env:GFORTH_WIN_HISTORY = "1"
$env:GFORTH_WIN_HISTORY_FILE = ".gforth-history"
.\build\native\gforth.exe
```

When `GFORTH_WIN_HISTORY` is unset, the default Windows interactive path does
not write a history file.

Opt-in reduced history navigation:

```powershell
$env:GFORTH_WIN_HISTORY_NAV = "1"
$env:GFORTH_WIN_HISTORY_FILE = ".gforth-history"
.\build\native\gforth.exe
```

In this reduced mode, `Ctrl-P` on an empty input line recalls the last line from
the selected history file.  Full multi-entry history navigation is still
reserved for a later phase.

Opt-in selected `ekey` escape sequences:

```powershell
$env:GFORTH_WIN_EKEY = "1"
$env:GFORTH_WIN_HISTORY_NAV = "1"
$env:GFORTH_WIN_HISTORY_FILE = ".gforth-history"
.\build\native\gforth.exe
```

In this mode, ANSI Up recalls the last history line.  ANSI Down, PageUp, and
PageDown are consumed safely as placeholders instead of being inserted as
literal escape text.

Opt-in compact resize marker:

```powershell
$env:GFORTH_WIN_WINCH = "1"
.\build\native\gforth.exe
```

In this mode, a pending `winch?` flag is surfaced internally as `k-winch`,
consumed by the compact editor path, and used to refresh `form` without
inserting text into the input buffer.

Integrated reduced interactive mode:

```powershell
$env:GFORTH_WIN_INTERACTIVE = "1"
$env:GFORTH_WIN_HISTORY_FILE = ".gforth-history"
.\build\native\gforth.exe
```

This single opt-in enables the reduced history persistence, `Ctrl-P`/ANSI Up
history recall, selected escape-sequence handling, and compact `k-winch`
handling.  The individual flags remain available for narrower testing.

Interactive startup:

```powershell
.\build\native\gforth.exe
```

Recreate the installer from an existing native build:

```powershell
.\scripts\build-installer.ps1
```
