# Changelog

Release history of the Windows-native fork (`fukuyori/gforth_for_windows`).
Version format: `<upstream base>+fukuyori.<major>.<minor>`.  Entries were
compiled from the git history, the GitHub release notes, and
`WINDOWS-RELEASE-3.1.md`; commit hashes are given for traceability.

## 0.7.9_20260923+fukuyori.3.2 (2026-10-03)

Upstream sync and signed-installer support.

### Upstream
- Merged forthy42/gforth master (`0.7.9_20260923`, 180 new commits, 69 files).
- New upstream features include the `e.` / `e.p` / `e.exact` words, new
  compare-and-branch superinstructions, `STACK>` / `BACK>` underflow checks,
  the Video4Linux2 viewer (minos2), mixed `ENGINECC` builds, and the
  `NEWS` -> `NEWS.md` conversion.  Details: `NEWS.md`.
- `status-line.fs`: kept the fork's guarded version and ported the upstream
  changes (`.stacks` precision `#16/#7`; the status bar is disabled when an
  exception occurs while drawing it).
- Generated artifacts (`prim.b`, `engine/*.i`, `kernel/{prim,aliases}.fs`,
  `kernl64l.fi`) were regenerated with a WSL Gforth host.

### Build and release
- `scripts/build-installer.ps1 -Sign`: signs `gforth.exe`, `gforth-ditc.exe`,
  the uninstaller and the setup exe with the certificate named by
  `CODESIGN_CERT` (`scripts/signing.ps1`, `SignTool` / `SignedUninstaller` in
  `installer/gforth-native.iss`).  `-TimestampUrl` overrides the timestamp server.

### Documentation
- Windows documents and `LICENSE-NOTICE-TEMPLATE.md` moved under `docs/`;
  README links updated.
- Added `docs/version-update-checklist.md` and this changelog.

## 0.7.9_20260708+fukuyori.3.1 (2026-07-18)

See `WINDOWS-RELEASE-3.1.md` for causes, fixes and verification.

- Fixed `gforth-advanced.fi` failing with `Checksum of image (...) does not
  match the executable` after Windows chose a different ASLR address.  The
  normal runtime is now an indirect-threaded engine; relocatable image
  creation uses a separate doubly indirect-threaded engine (`gforth-ditc.exe`).
- Fixed an argument-free release build picking the installed fork as its
  bootstrap host (`cannot open image file .../gforth.fi`).
- Docs: Windows image internals (`doc/For-Windows-Imagefile.md`,
  `WINDOWS-RELEASE-3.1.md`).

## 0.7.9_20260708+fukuyori.3.0 (2026-07-11)

- Merged upstream `0.7.9_20260708` (51 commits / 62 files): `see fconstant`,
  `bt-location`, `BARRIER`, `latest-name`, string-literal recognizer and
  modified-key F1-F4 fixes; new `rec-prefix.fs`; `random.fs` in the image;
  `marker` rewrite; `libc.fs` / `pthread.fs` no longer abort startup when the
  library is missing; guards for cross-compiling from older snapshots.
- `build-native.ps1 -SkipBootstrap`: build from pre-generated artifacts when
  no full-image bootstrap Gforth exists; documented the upstream sync flow and
  bootstrap requirements (`WINDOWS-NATIVE.md`).
- Installer: reject advanced images composed from two intermediate images
  loaded at the same base address, and rebuild (up to 4 rounds) until a smoke
  test that compiles and runs a colon definition passes.

## 0.7.9_20260415+fukuyori.2.3 (2026-05-03 release; launcher change 2026-06-08)

- Regenerate the advanced interactive image at install time
  (`generate-installed-advanced.ps1`, `run-advanced.ps1`).
- Installed layout gets `gforth-advanced.cmd`; Start menu / desktop shortcuts
  and the post-install launch default to advanced mode (status bar + history),
  falling back to the plain image if the advanced image is missing.
  Plain mode remains available as `gforth.exe`.

## 0.7.9_20260415+fukuyori.2.0 - 2.2 (2026-04-23 to 2026-04-24)

Interactive-console recovery work on Windows (see `WINDOWS-INTERACTIVE-PLAN.md`,
`WINDOWS-INTERACTIVE-BASELINE.md`, `WINDOWS-TERMINAL-CONTRACT.md`).

- 2.0: added the interactive plan, baseline and terminal-contract documents;
  console input/output changes in `engine/io.c` and `engine/support.c`.
- 2.1 / 2.2: continued console and key-handling work (`engine/io.c`,
  `ekey.fs`, `compat/win32/src/win32_compat.c`).
- Detailed per-version contents are in the baseline document.

## 0.7.9_20260415+fukuyori.1.1 (2026-04-19)

- Native Windows build and installer flow separated (`build-native.ps1`,
  `build-installer.ps1`); console I/O changes in `engine/io.c` and
  `engine/main.c`; rewritten README and `WINDOWS-NATIVE.md`.
- Added fork synchronization notes.

## 0.7.9_20260415+fukuyori.1.0 (2026-04-18)

Initial import with Windows-native build support:

- build `gforth.exe` with a native Windows toolchain (clang);
- keep the self-hosted bootstrap flow working from a Windows machine;
- usable interactive REPL in a normal Windows console;
- installer that ships only the files needed at runtime.

The implementation keeps the upstream tree intact as far as possible and adds
a Windows compatibility layer (`compat/win32/`) plus a native build script.

---

Note: the GitHub release `0.7.9_20260610` (published 2026-07-05, "for mac")
is not described here; no matching entry was found in the Windows fork history.
