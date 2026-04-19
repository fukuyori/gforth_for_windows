# Windows Native Build Notes

This repository is a fork of
[forthy42/gforth](https://github.com/forthy42/gforth) that adds a native
Windows build, runtime fixes for interactive terminals, and an Inno Setup
installer flow.  The current fork release is based on `Gforth 0.7.9_20260415`
and is versioned as `0.7.9_20260415+fukuyori.1.1`.

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

Installer build from an existing native build:

```powershell
.\scripts\build-installer.ps1 -SkipNativeBuild
```

Full native build plus installer:

```powershell
.\scripts\build-installer.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe"
```

The native build produces:

- `build/native/gforth.exe`
- `build/native/gforth.fi`

The installer build produces:

- `build/installer/output/gforth-native-<version>-x64-setup.exe`

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

Interactive startup:

```powershell
.\build\native\gforth.exe
```

Recreate the installer from an existing native build:

```powershell
.\scripts\build-installer.ps1 -SkipNativeBuild
```
