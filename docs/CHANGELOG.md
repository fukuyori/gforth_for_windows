# Changelog

Release history of the Windows-native fork (`fukuyori/gforth_for_windows`).
Version format: `<upstream base>+fukuyori.<major>.<minor>`.  Entries were
compiled from the git history, the GitHub release notes, and
`WINDOWS-RELEASE-3.1.md`; commit hashes are given for traceability.

## Unreleased

### Build and installer
- `build-release.ps1 -SkipNative` now runs a preflight
  (`scripts/release-preflight.ps1`) before staging `build/native`, and stops
  when the engine is older than its sources, `gforth.exe` reports a different
  version than `configure.ac`, `kernl64l.fi` is older than the kernel sources,
  or `build/native/gforth.fi` is not the current `kernl64l.fi`.  `-AllowStale`
  turns these failures into warnings.

## 0.7.9_20260923+fukuyori.3.4 (2026-10-14)

### Fixed
- `see` crashed (access violation) on most words of the advanced image, e.g.
  `see decode`.  The Windows `sigaction()` emulation (`compat/win32`) used the C
  runtime's `signal()`, which resets the handler to `SIG_DFL` on every delivery,
  so the second invalid memory access in a process terminated it instead of
  throwing -9; `see` probes literals as addresses and hits that.  The emulation
  now keeps the handler installed (a trampoline re-arms it before calling the
  real handler).
- `SA_SIGINFO` handlers (`segv_handler`, `fpe_handler`) used to be called with
  undefined second/third arguments.  They now get the fault address
  (`si_addr`, from the CRT's `__pxcptinfoptrs()`) and POSIX `FPE_*` codes, so
  stack faults are reported as in Gforth on Unix: stack underflow -4, stack
  overflow -3, return stack overflow -5 (previously all -9).
- Integer division by zero (`1 0 /`, `mod`, `/mod`, `*/`, `um/mod`, ...)
  terminated the process (exception 0xC0000094) instead of throwing -10: the C
  runtime does not deliver it as `SIGFPE`, not even in a minimal C program.
  The compat layer now hooks the top-level exception filter (the place the CRT
  uses for `SIGSEGV`) and hands integer divide-by-zero and the `INT_MIN / -1`
  overflow to the SIGFPE handler: `1 0 /` throws -10, `INT_MIN -1 /` throws -11.

## 0.7.9_20260923+fukuyori.3.3 (2026-10-14)

### Fixed
- The status bar width was not recalculated after the window was resized:
  Windows never raises `SIGWINCH`, so `rows`/`cols` kept the startup size and
  the bar wrapped when the window was narrower than at startup.  A console
  watcher thread (`engine/io.c`) now detects size changes, interrupts the
  blocked read (`ekey` returns `k-winch`), and `status-line.fs` redraws the bar
  for the new width via the new `win-winch-hook` (`kernel/accept.fs`).
  `GFORTH_WIN_NO_WINSIZE_WATCH` disables the watcher.  The kernel image must be
  regenerated (`scripts\regen-bootstrap.ps1`) because `kernel/accept.fs` changed.

### Build and installer
- `regen-bootstrap.ps1` records the inputs of `kernl64l.fi` (`kernl64l.fi.inputs`)
  and the image builder warns, naming the changed files, when the kernel image is
  older than its sources or differs from the default `gforth.fi`.  It also
  refreshes the generated support files (`kernel/version.fs`, ...) first, so a
  version bump is no longer built into the kernel from a stale `version.fs`.
- `build-advanced-interactive-image.ps1` checks that the kernel image matches
  the engine before building (previously a mismatch failed with
  `Primitive ... is not implemented by this engine`) and its smoke test now also
  compiles and runs a colon definition.
- The installer reports a failed advanced-image generation (message with the log
  path) instead of silently starting in plain mode; `gforth-advanced.cmd` says
  so when it falls back.
- Added `scripts/regen-bootstrap.ps1` / `regen-bootstrap-wsl.sh` and the
  tagged-upstream sync policy (README).

### Known issue (not fixed)
- `see` crashes (access violation) on some words of the advanced image, e.g.
  `see decode`; reproduced with the installed 3.2 as well.

## 0.7.9_20260923+fukuyori.3.2 (2026-10-03)

Upstream sync and signed-installer support.

### Upstream
- Merged forthy42/gforth master up to `f847d479` (2026-09-28): 180 new
  commits, 69 files.  This includes the upstream tag `0.7.9_20260923`
  (`448860b6`, 2026-09-23) **and 10 commits after it** (8 non-merge commits,
  7 files; see "Applied beyond the tag" below).  Future syncs are limited to
  tagged versions.
- New upstream features include the `e.` / `e.p` / `e.exact` words, new
  compare-and-branch superinstructions, `STACK>` / `BACK>` underflow checks,
  the Video4Linux2 viewer (minos2), mixed `ENGINECC` builds, and the
  `NEWS` -> `NEWS.md` conversion.  Details: `NEWS.md`.

### Applied beyond the tag (2026-09-23 to 2026-09-28)
Upstream changes after `0.7.9_20260923` that are present in this release:
- `NEWS` -> `NEWS.md` conversion finished; `NEWS.md` work (`ccc370a7`,
  `882368d4`, `2b917440`, `921aad7f`).
- `NEWS.html` links for words; new `news-links.fs` (`7cff6c15`, `6a6db126`).
- Working mixture of GCC for the engine and Clang for the rest
  (`ENGINECC`; `Makefile.in`, `engine/Makefile.in`; `8ede08e9`).
- `install-deps.sh` builds pcre and gforth from source when the `apt-get`
  install fails (`923959b0`); `flatpak/org.gforth.gforth.yml` update.
- `doc/words/1.0-words` regenerated.
- These files are presumably not used by the Windows-native build (not
  verified; the built executables were not compared against a tag-only build).

Upstream `master` after 2026-09-28: one new commit, `4e5ffe8b` "added F*+"
(2026-10-08, new primitive `f*+`; changes `prim`, `NEWS.md`,
`doc/gforth.texi.in`).  It has been taken into upstream `master` but is **not**
merged into this fork's `main` (checked 2026-10-11).
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
