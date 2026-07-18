# License and Distribution Notice Templates

This file contains English notice templates for this fork when
publishing source releases, binary releases, and Windows installers.

These templates are intended to make GPL-related notices clearer and
more consistent.  Keep the existing copyright and license notices in the
source tree intact.

## Project-Specific Values

Use these values when preparing notices for this repository:

```text
Fork repository:
https://github.com/fukuyori/gforth_for_windows

Upstream repository:
https://github.com/forthy42/gforth

Base version:
Gforth 0.7.9_20260708

Fork release version:
0.7.9_20260708+fukuyori.3.1

Maintainer:
fukuyori

Contact:
self@spumoni.org
```

## Repository Notice

Use this near the top of `README.md` or in the repository description:

```text
This repository is a fork of https://github.com/forthy42/gforth and is
based on Gforth 0.7.9_20260708.

This fork contains Windows-native build, runtime, and packaging changes.
Unless otherwise noted in individual files, the work is distributed
under the same license terms as the upstream Gforth sources.

Maintainer: fukuyori <self@spumoni.org>
```

## Modified Version Notice

Use this in release notes or project documentation when you want to
state clearly that this is a modified version:

```text
This is a modified version of Gforth, based on Gforth 0.7.9_20260708
from the forthy42/gforth repository.

This fork adds Windows-native compatibility, build scripts, and an
Inno Setup-based installer flow.

Modified by: fukuyori <self@spumoni.org>
Fork repository: https://github.com/fukuyori/gforth_for_windows
Modification date: <YYYY-MM-DD>
```

## Source Release Notice

Use this when publishing a source archive or source tag:

```text
Source release for the Windows-native Gforth fork.

This release is based on Gforth 0.7.9_20260708 from
https://github.com/forthy42/gforth and contains local modifications.

Fork repository:
https://github.com/fukuyori/gforth_for_windows

Maintained by:
fukuyori <self@spumoni.org>

The source code in this release is provided under the applicable license
terms already present in the source tree, including the GNU General
Public License where applicable.  Please keep all existing copyright and
license notices intact.
```

## Binary or Installer Release Notice

Use this alongside a `.zip`, `.exe`, or installer download:

```text
Windows binary release of a modified Gforth fork based on
Gforth 0.7.9_20260708 from https://github.com/forthy42/gforth.

Corresponding source for this exact binary release is available at:
https://github.com/fukuyori/gforth_for_windows/releases/tag/<tag>

Fork repository:
https://github.com/fukuyori/gforth_for_windows

Maintainer:
fukuyori <self@spumoni.org>

This release includes Windows-native build and packaging changes.
Please refer to the included license files and source tree notices for
the applicable copyright and license terms.
```

## GitHub Release Page Template

Use this in a GitHub Release description:

```text
This release contains a Windows-native build of this Gforth fork.

Base version:
- Gforth 0.7.9_20260708
- upstream fork source: https://github.com/forthy42/gforth
- fork repository: https://github.com/fukuyori/gforth_for_windows

This release contains local modifications for:
- Windows-native compatibility
- PowerShell-based native build
- Windows console fixes
- Inno Setup packaging

Corresponding source for this exact release:
- https://github.com/fukuyori/gforth_for_windows/releases/tag/<tag>

Maintainer:
- fukuyori <self@spumoni.org>

License:
- See the license files included in the source tree and release package.
- Existing upstream copyright and license notices remain in effect.
```

## Installer README Snippet

Use this in an installer README, download page, or release announcement:

```text
This installer packages a modified Windows-native build of Gforth based
on Gforth 0.7.9_20260708.

Upstream source:
https://github.com/forthy42/gforth

Corresponding source for this installer:
https://github.com/fukuyori/gforth_for_windows/releases/tag/<tag>

Fork repository:
https://github.com/fukuyori/gforth_for_windows

Maintainer:
fukuyori <self@spumoni.org>

This package includes local Windows-native build and runtime changes.
See the included license files for additional details.
```

## Short Attribution Line

Use this where only a short attribution fits:

```text
Forked from forthy42/gforth, based on Gforth 0.7.9_20260708.
```
