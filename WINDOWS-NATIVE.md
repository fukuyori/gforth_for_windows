# Windows Native Build Notes

This document describes the changes that were made to build and run
Gforth on Windows without relying on MSYS2 or MinGW at runtime.  The
target is a native Windows executable built with LLVM/Clang and
packaged with Inno Setup.

## Goals

The Windows-native work had four practical goals:

- build `gforth.exe` with a native Windows toolchain
- keep the self-hosted bootstrap flow working from a Windows machine
- make the interactive REPL usable in a normal Windows console
- produce an installer that ships only the files needed at runtime

The implementation keeps the existing Gforth source tree intact as much
as possible.  Instead of replacing the Unix-oriented build, it adds a
Windows-specific compatibility layer and a native build script.

## Current Build Entry Points

Native build:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe"
```

Installer build:

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

## Summary of the Port

### 1. Windows compatibility layer

The original engine assumes a Unix/POSIX environment and includes APIs
such as `unistd.h`, `dirent.h`, `pwd.h`, `termios.h`, `sys/mman.h`,
`sys/ioctl.h`, `sys/resource.h`, and `sys/time.h`.  Windows does not
provide these interfaces directly.

To bridge that gap, a compatibility layer was added under:

- `compat/win32/include`
- `compat/win32/src/win32_compat.c`

This layer provides the minimum surface needed by the engine:

- POSIX-like file and directory access
- `mmap`/`munmap` style memory mapping helpers
- `gettimeofday` and `getrusage` equivalents
- `getpwuid`/`getpwnam` style account lookup
- console-mode helpers for terminal behavior
- signal compatibility, including `SIGWINCH`

The Win32 config template in `compat/win32/native-config.h.in` also
defines Windows-specific compile-time properties for the native build.
In particular:

- `SMALL_OFF_T` was set to match the Windows file-offset model
- `DIRSEP` was corrected to `\\` so path and newline-related code uses
  Windows semantics consistently

### 2. Native build script for bootstrap and compilation

`scripts/build-native.ps1` is the native build entry point.  It replaces
the Unix `configure`/`make` path with a PowerShell-driven build that can
run on a regular Windows installation.

The script is responsible for:

- locating the bootstrap `gforth.exe`
- locating `gforth.fi` for the bootstrap system when needed
- locating `m4.exe` when available
- generating primitive tables and kernel-generated files
- compiling the native Windows compatibility layer and engine objects
- linking `build/native/gforth.exe`
- copying the generated image to `build/native/gforth.fi`

The bootstrap stage still uses a working Gforth because the build is
partially self-hosted.  The script automates the Windows-specific part
of that process so the user does not have to run the Unix build scripts.

### 3. Generated image handling

The executable expects `gforth.fi` by default.  During the early native
port, the build produced `kernl64l.fi`, but `gforth.exe` still searched
for `gforth.fi` unless `-i` was supplied manually.

The build now resolves this in two ways:

- `scripts/build-native.ps1` still generates `kernl64l.fi`
- the same script copies the generated image to `build/native/gforth.fi`

This means the following now works without extra arguments:

```powershell
.\build\native\gforth.exe
```

### 4. Image loading on Windows

The original image-loading path in `engine/main.c` was written with
Unix-style file-backed `mmap` assumptions.  On Windows, the image mapping
could fail and leave the runtime trying to execute from uninitialized
memory.

The Windows-native path now falls back to `fread()` when file-backed
mapping is not available.  This ensures the image is actually loaded
into memory and that `boot_entry` and related startup state are valid.

Without that fix, the executable could be built successfully but fail at
startup.

## Interactive Console Fixes

The most visible runtime problem during the port was interactive console
behavior.

### Symptom

When the native executable was started in a normal Windows console:

- Enter sometimes needed to be pressed twice
- typed characters appeared one keystroke late
- the REPL could report terminal-related errors

### Root cause

The Unix terminal preparation logic in `engine/io.c` tried to put the
terminal into a raw/non-canonical mode.  That model does not map cleanly
to the Windows console API, especially around how Enter is handled.

The issue was not just newline bytes in isolation.  It was the terminal
mode transition around Enter processing.

### Final fix

For `_WIN32`, `prep_terminal()` and `deprep_terminal()` in
`engine/io.c` now avoid forcing the console into the Unix-style raw
mode.  The Windows console stays in cooked mode, so Enter remains a
normal line terminator managed by the host console.

This change was the one that fixed the "press Enter twice" problem.

### Additional console input work

`engine/support.c` also gained a Windows console line-input path based
on `ReadConsoleA`.  This path:

- detects whether the stream is really a console
- temporarily enables line input, echo, and processed input
- reads one console line
- normalizes CR/LF handling before passing data back to Gforth

This keeps the higher-level runtime logic away from CRT buffering quirks
when Windows console input is involved.

### SIGWINCH handling

The runtime also expects `SIGWINCH`-related state.  Windows does not
define this signal, so the compatibility layer now declares a synthetic
`SIGWINCH` value and handles it in the Win32 signal shim.  The build
script also patches generated primitive metadata so `winch?` can return
`NULL` safely when the signal is not available.

## Build Warning Cleanup

The Windows-native port also cleaned up several warning classes that
became more visible with Clang on Windows:

- old-style non-prototype declarations in `engine/getopt.h`
- old-style non-prototype declarations in `engine/fnmatch.h`
- format mismatches in `engine/main.c`
- pointer-sign issues in generated primitive-related code
- offset-size assumptions exposed by Windows 64-bit builds

These changes do not define the port by themselves, but they make the
native build easier to keep healthy and reduce the chance that the build
breaks later when compiler strictness increases.

## Installer and Distribution Layout

The Windows-native packaging flow is built around three files:

- `scripts/stage-native-dist.ps1`
- `scripts/build-installer.ps1`
- `installer/gforth-native.iss`

### Staging

`scripts/stage-native-dist.ps1` creates `build/installer/stage` from the
native build output.

The script originally staged a very broad slice of the repository.  It
was later reduced to focus on runtime content:

- `gforth.exe`
- `gforth.fi`
- root `.fs`, `.fb`, and `.4th` files
- selected root documentation files
- `compat`
- `kernel`
- `unix` files needed for runtime loading
- `wordlibs` runtime support files

Large development-oriented trees such as `arch`, `doc`, and `engine`
are no longer staged for the installer.

This reduced the stage size significantly while keeping the runtime
usable.

### Inno Setup

`installer/gforth-native.iss` builds a per-user x64 installer.

Important choices in the installer:

- install location is `{localappdata}\Programs\Gforth`
- no administrator privileges are required
- PATH modification is optional
- Start Menu and optional desktop shortcuts are created
- the installer runs `gforth.exe` after installation if requested

The installer consumes the staged tree recursively, so the staging step
defines the contents of the final package.

## Files Most Directly Involved

The following files contain the core Windows-native work:

- `compat/win32/include/*`
- `compat/win32/src/win32_compat.c`
- `compat/win32/native-config.h.in`
- `engine/io.c`
- `engine/support.c`
- `engine/main.c`
- `engine/getopt.h`
- `engine/fnmatch.h`
- `scripts/build-native.ps1`
- `scripts/stage-native-dist.ps1`
- `scripts/build-installer.ps1`
- `installer/gforth-native.iss`

## Known Limitations

This work establishes a native Windows build and packaging path, but it
does not claim that every Forth source file in the repository is fully
validated in the Windows-native configuration.

In particular:

- the build remains bootstrap-dependent on an existing Gforth
- some optional library-loading paths are still Unix-oriented
- some Forth files currently fail in the same way both inside and
  outside the staged installer tree, so they are not installer-specific
  regressions

The current goal is a reliable native executable, a usable interactive
REPL, and a reproducible installer flow.

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
