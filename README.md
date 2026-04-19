# Gforth README

This repository is a fork of
[forthy42/gforth](https://github.com/forthy42/gforth) that has been modified so
Gforth can be built, run, and packaged natively on Windows.  It is currently
based on `Gforth 0.7.9_20260415` and this fork's current release version is
`0.7.9_20260415+fukuyori.1.1`.

Gforth is a fast and portable implementation of ANS Forth and Forth 200x.  The
upstream project remains the base of this repository; this fork adds a native
Windows build path, Windows terminal fixes, and an Inno Setup-based installer
flow.

## What This Fork Adds

Compared with the upstream repository, this fork currently focuses on:

- native Windows builds without requiring MSYS2 or MinGW at runtime
- a usable interactive REPL in Windows Terminal and WezTerm
- Windows packaging with a per-user Inno Setup installer
- PowerShell scripts for native build, staging, and installer creation

For the Windows-specific implementation details, see `WINDOWS-NATIVE.md`.

## Quick Start

### Native Windows build

Build a native `gforth.exe` and `gforth.fi` on Windows:

```powershell
.\scripts\build-native.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe"
```

This produces:

- `build/native/gforth.exe`
- `build/native/gforth.fi`

Run the native build:

```powershell
.\build\native\gforth.exe
```

Smoke test:

```powershell
.\build\native\gforth.exe -e '1 2 + . cr bye'
```

### Windows installer

Create the installer from an existing native build:

```powershell
.\scripts\build-installer.ps1 -SkipNativeBuild
```

Or build everything in one step:

```powershell
.\scripts\build-installer.ps1 -BootstrapExe "C:\Program Files (x86)\gforth\gforth.exe"
```

The installer output is written to:

- `build/installer/output/gforth-native-<version>-x64-setup.exe`

### Upstream-style builds

This repository still contains the normal upstream source tree and build
machinery for Unix-like systems.  For those paths, see:

- `INSTALL`
- `INSTALL.md`
- `INSTALL.BINDIST`

## Documentation Guide

Use these entry points depending on what you want to do:

- `WINDOWS-NATIVE.md`: native Windows build, terminal behavior, and installer flow
- `INSTALL.md`: build from source, especially from git
- `INSTALL`: general installation notes from the traditional build flow
- `INSTALL.BINDIST`: installation from binary distributions
- `LICENSE-NOTICE-TEMPLATE.md`: release and installer notice templates for this fork

## Repository Layout

The files most relevant to the Windows-native fork are:

- `compat/win32/`: Windows compatibility headers and source
- `engine/`: runtime and terminal handling code
- `kernel/`: Forth kernel sources, including interactive input handling
- `scripts/build-native.ps1`: native Windows build entry point
- `scripts/stage-native-dist.ps1`: installer staging step
- `scripts/build-installer.ps1`: Inno Setup wrapper
- `installer/gforth-native.iss`: Windows installer definition

The wider tree still contains the upstream Gforth sources, examples, add-ons,
tests, and packaging files for other environments.

## Fork Synchronization

In this fork, `origin` is expected to point to the fork repository and
`upstream` is expected to point to the original repository.

Check your remotes:

```powershell
git remote -v
```

Bring upstream changes into this fork with a merge:

```powershell
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

If you prefer a linear history, replace `merge` with `rebase`:

```powershell
git fetch upstream
git checkout main
git rebase upstream/main
git push origin main
```

Normal development should push to `origin`, not to `upstream`.

## Upstream Project and Support

The upstream Gforth project is part of the GNU Operating System and remains the
base project for this fork.  General Gforth discussion and support still follow
the usual upstream channels:

- Usenet: `comp.lang.forth`
- Mailing list: `gforth@gnu.org`
- Bug tracker: <https://savannah.gnu.org/bugs/?func=addbug&group=gforth>

If you are publishing releases from this fork, keep the existing upstream
copyright and license notices intact.

## License

Gforth is distributed under the GNU General Public License; see `COPYING`.

---

Authors: Bernd Paysan, Anton Ertl, Gerald Wodni
Copyright (C) 1995,1996,1997,1998,2000,2003,2004,2006,2007,2008,2009,2016,2017,2018,2019,2020,2021,2022,2023 Free Software Foundation, Inc.

This file is part of Gforth.

Gforth is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see http://www.gnu.org/licenses/.
