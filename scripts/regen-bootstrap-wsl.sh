#!/usr/bin/env bash
# Regenerate the bootstrap artifacts of the Windows-native build with a full
# Gforth running in WSL (or any Linux).  Run from anywhere; the repository root
# is derived from this script's location.
#
# Regenerated (all git-ignored):
#   prim.b, engine/*.i, kernel/prim.fs, kernel/aliases.fs, kernl64l.fi
#
# Mirrors Generate-BootstrapArtifacts in scripts/build-native.ps1, including its
# post-processing (CRLF-preserving prim.b patches, "newline" constant).
# Needed after merging upstream changes to `prim`, `kernel/` or the startup
# libraries, and on a fresh clone.  Not needed for ordinary rebuilds.
#
# Requirements: gforth (full image), m4, python3.
# Environment:
#   GFORTH           gforth command (default: gforth)
#   GFORTH_BOOT_DIRS colon-separated library dirs (default: auto-detected from
#                    the version reported by `gforth --version`)
#
# After this script, on Windows:
#   .\scripts\build-native.ps1 -SkipBootstrap
#   copy kernl64l.fi build\native\gforth.fi
# (scripts/regen-bootstrap.ps1 does all of it.)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GFORTH="${GFORTH:-gforth}"
for tool in "$GFORTH" m4 python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found" >&2; exit 1; }
done

if [ -n "${GFORTH_BOOT_DIRS:-}" ]; then
    LIBDIRS="$GFORTH_BOOT_DIRS"
else
    version="$("$GFORTH" --version 2>&1 | awk '{print $2; exit}')"
    LIBDIRS=""
    for base in /usr/local/lib/gforth /usr/local/share/gforth /usr/lib/gforth /usr/share/gforth; do
        if [ -d "$base/$version" ]; then LIBDIRS="${LIBDIRS:+$LIBDIRS:}$base/$version"; fi
        if [ -d "$base/site-forth" ]; then LIBDIRS="${LIBDIRS:+$LIBDIRS:}$base/site-forth"; fi
    done
    [ -n "$LIBDIRS" ] || { echo "error: no library directory found for gforth $version; set GFORTH_BOOT_DIRS" >&2; exit 1; }
fi
echo "gforth: $("$GFORTH" --version 2>&1 | head -1)"
echo "library path: $LIBDIRS"

G=("$GFORTH" --die-on-signal -m64M -p ".:$ROOT:$LIBDIRS")

# The cross build rewrites this tracked file; restore it afterwards.
CROSSDOC=doc/crossdoc.fd.tmp
[ -f "$CROSSDOC" ] && cp -p "$CROSSDOC" "$CROSSDOC.regen-bak"
restore_crossdoc() {
    if [ -f "$CROSSDOC.regen-bak" ]; then mv -f "$CROSSDOC.regen-bak" "$CROSSDOC"; fi
}
trap restore_crossdoc EXIT

mkdir -p build/native

echo "== prim.b =="
m4 -Dcondbranch_opt=0 prim > prim.b
python3 - <<'PY'
import re
p = 'prim.b'
s = open(p, newline='', encoding='utf-8').read()
patches = [
    ("#ifdef HAS_FILE\r\nfflush(stdout);\r\nn = key((FILE*)wfileid);",
     "#ifdef HAS_FILE\r\nn = key((FILE*)wfileid);"),
    ("#ifdef HAS_FILE\r\nfflush(stdout);\r\nf = key_query((FILE*)wfileid);",
     "#ifdef HAS_FILE\r\nf = key_query((FILE*)wfileid);"),
]
for a, b in patches:
    s = s.replace(a, b)
# Upstream already guards winch_addr with SIGWINCH; patch only if it does not.
s, n = re.subn(r"(winch\? \( -- a_addr \)\s+gforth-internal winch_query\s+)a_addr = &winch_addr;",
               lambda m: m.group(1) + "#ifdef SIGWINCH\r\na_addr = &winch_addr;\r\n#else\r\na_addr = NULL;\r\n#endif", s)
open(p, 'w', newline='', encoding='utf-8').write(s)
PY

gen() {  # gen <forth code> <output file>
    "${G[@]}" prims2x.fs -e "$1" > "$2"
}

echo "== engine/*.i =="
gen "c-flag on s\" prim.i\" save-mem out-filename 2! s\" prim.b\" ' output-c ' output-c-combined process-file bye" engine/prim.i
gen "c-flag on s\" prim.b\" ' output-label dup process-file bye" engine/prim_lab.i
gen "c-flag on s\" prim.b\" ' noop dup process-file bye" engine/prim_grp.i
gen "c-flag on s\" prim.b\" ' output-forthname ' output-forthname-combined process-file bye" engine/prim_names.i
gen "c-flag on s\" prim.b\" ' output-superend dup process-file bye" engine/prim_superend.i
gen "c-flag on s\" prim.b\" ' output-costs-gforth-simple ' output-costs-gforth-combined process-file bye" engine/costs.i
gen "c-flag on s\" prim.b\" ' output-c-prim-num ' noop process-file bye" engine/prim_num.i
gen "c-flag on s\" prim.b\" ' output-super2-simple ' output-super2-combined process-file bye" engine/super2.i

echo "== kernel/aliases.fs, kernel/prim.fs =="
cp kernel/aliases0.fs kernel/aliases.fs-
gen "forth-flag on s\" prim.b\" ' output-alias ' noop process-file bye" kernel/aliases.fs.generated
cat kernel/aliases.fs.generated >> kernel/aliases.fs-
mv -f kernel/aliases.fs- kernel/aliases.fs
rm -f kernel/aliases.fs.generated

cp kernel/prim0.fs kernel/prim.fs-
gen "forth-flag on s\" prim.b\" ' output-forth ' output-forth-combined process-file bye" kernel/prim.fs.generated
cat kernel/prim.fs.generated >> kernel/prim.fs-
mv -f kernel/prim.fs- kernel/prim.fs
rm -f kernel/prim.fs.generated
# Windows console uses CRLF newlines in the kernel
sed -i 's/Create "newline e? crlf \[IF\] 2 c, \$0D c, \[ELSE\] 1 c, \[THEN\] \$0A c,/Create "newline 2 c, $0D c, $0A c,/' kernel/prim.fs

echo "== kernl64l.fi (cross build) =="
"${G[@]}" -e "fpath= .|./kernel|~+|." -e 's" mach64l.fs" include kernel/main.fs' \
    -e "save-cross kernl64l.fi- build/native/gforth.exe bye" > build/native/regen-cross.log 2>&1 \
    || { tail -20 build/native/regen-cross.log >&2; echo "error: cross build failed (see build/native/regen-cross.log)" >&2; exit 1; }
mv -f kernl64l.fi- kernl64l.fi

echo "REGEN-OK"
