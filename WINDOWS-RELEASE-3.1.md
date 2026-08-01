# Windows Native Release 3.1 Fix Record

This document records the Windows-native runtime and release-build fixes
included in `0.7.9_20260708+fukuyori.3.1`.

## Summary

The release fixes two related Windows problems:

1. `gforth-advanced.fi` could fail after Windows selected a different ASLR
   address:

   ```text
   Checksum of image (...) does not match the executable
   ```

2. An argument-free release build could select the fork installed under
   `%LOCALAPPDATA%\Programs\Gforth` as its bootstrap host and fail while
   generating `engine/prim.i`:

   ```text
   cannot open image file .../gforth.fi
   Native advanced interactive image build failed.
   ```

The release now uses an indirect-threaded engine for the normal Windows
runtime and a separate doubly indirect-threaded engine for relocatable image
creation.  The normal release entry point is:

```powershell
.\scripts\build-release.ps1
```

## Root Causes

### Direct-threaded runtime instability

The previous Windows runtime used the direct-threaded engine.  Extending an
image could run `compile-prims` against an address layout that changed under
Windows ASLR, resulting in intermittent access violations.

The normal `gforth.exe` now uses the indirect-threaded engine, which does not
use that conversion path.

### Advanced image tied to one executable layout

The image checksum in `engine/main.c` depends on the runtime primitive table.
An advanced image composed without independent code, xt, and label relocation
bases could remain tied to the executable layout present when the image was
created.  It could therefore load successfully immediately after creation but
fail after a reboot or another ASLR layout change.

`gforth-ditc.exe` is now built with the doubly indirect-threaded engine and is
used for both intermediate image saves and final image composition.  Image
creation rejects the diagnostic:

```text
images have the same base address
```

The normal runtime remains `gforth.exe`; `gforth-ditc.exe` is a packaging
helper.

### Invalid automatic bootstrap selection

The fork installed under `%LOCALAPPDATA%\Programs\Gforth` contains a compact
kernel image.  That image cannot host `prims2x.fs` or the cross compiler, but
the build script previously selected it automatically.

Automatic bootstrap selection is now restricted to an official full-image
Gforth installation under `Program Files`.  If one is not available, the
normal build uses the generated files already present in the source tree.
The installed fork can still be supplied explicitly for diagnosis, but it is
not a valid bootstrap host.

### Generated output truncation after a failed command

PowerShell output redirection opened `engine/prim.i` before starting the
bootstrap command.  When the command failed, the existing generated file was
left at zero bytes.

Generated command output is now written to a temporary file.  The destination
is replaced only after the command exits successfully and produces non-empty
output.

### Child-process working-directory mismatch

PowerShell's current location and the process-level current directory can
differ.  `build-advanced-interactive-image.ps1` used
`System.Diagnostics.ProcessStartInfo` without setting `WorkingDirectory`, so a
child Gforth process could fail to find files such as:

```text
to.fs
rec-sequence.fs
exboot.fs
startup.fs
```

Every Gforth child process launched by the advanced-image builder now receives
the repository root as its explicit working directory.

### Windows x64 format warnings

Windows uses the LLP64 data model: `unsigned long` is 32-bit while `Cell` is
64-bit.  Debug output used `%lx` for `Cell` values and produced Clang format
warnings.  These diagnostics now use `%llx` with explicit
`unsigned long long` conversions.

### Probe output during a normal build

The advanced-image readiness probe intentionally checks capabilities that the
compact image does not provide.  Its expected `[FAIL]` results were previously
printed during every release build and obscured the actual result.

The full capability matrix is now printed only with:

```powershell
.\scripts\build-advanced-interactive-image.ps1 -ProbeOnly
```

A normal release build prints only the image-generation results that determine
success or failure.

## Changed Components

- `engine/engine.c`
  - uses the correct 64-bit format for relocation offsets
- `engine/main.c`
  - uses the correct 64-bit format for primitive offsets
- `scripts/build-native.ps1`
  - builds the ITC runtime and DITC image builder
  - excludes the compact installed fork from automatic bootstrap selection
  - preserves existing generated output when a command fails
- `scripts/build-advanced-interactive-image.ps1`
  - uses `gforth-ditc.exe` for relocatable image construction
  - sets the child-process working directory explicitly
  - limits detailed capability probes to `-ProbeOnly`
- `scripts/generate-installed-advanced.ps1`
  - regenerates the installed advanced image with `gforth-ditc.exe`
- `scripts/stage-native-dist.ps1`
  - stages `gforth-ditc.exe`
- `scripts/build-release.ps1`
  - passes the DITC image builder through native and staged image creation
- `scripts/build-installer.ps1`
  - requires the DITC image builder in the staged release

## Release Procedure

Build and stage the release:

```powershell
.\scripts\build-release.ps1
```

The command must finish with:

```text
Release build staged at <repository>\build\installer\stage
```

Electronically sign these staged executables:

```text
build\installer\stage\gforth.exe
build\installer\stage\gforth-ditc.exe
```

After signing and verifying both files, create the installer:

```powershell
.\scripts\build-installer.ps1
```

Do not create the release installer before the staged executables have been
signed.

## Verification

The release was verified with:

```powershell
.\scripts\build-release.ps1
.\scripts\check-advanced-image-runtime.ps1
```

The following conditions passed:

- the release build completed with zero Clang format warnings
- the build completed even when the process-level current directory was
  deliberately set outside the repository
- the normal and staged advanced images passed compiled-colon smoke tests
- `savesystem`, `ekey`, history, `see`, `locate`, and status-line behavior
  passed the advanced runtime probe
- the startup banner reported
  `Gforth 0.7.9_20260708+fukuyori.3.1`
- repeated runtime tests did not reproduce the checksum mismatch

The unsigned release stage is created at:

```text
build\installer\stage
```

Installer creation remains a separate, post-signing step.
