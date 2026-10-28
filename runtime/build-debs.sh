#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the ILP32 runtime packages (biarch, Architecture: arm64) from install trees of Debian 13's
# glibc and gcc-14 built for aarch64-linux-gnu_ilp32 (stage/<package>/, DESTDIR style, not stripped,
# with stage/MANIFEST and stage/doc/). The packages install next to Debian's own LP64 libraries:
#   dynamic linker  /usr/lib/ld-linux-aarch64_ilp32.so.1   (PT_INTERP /lib/... via merged /usr)
#   libraries       /usr/libilp32                          (/libilp32 -> usr/libilp32)
# Nothing of Debian's own packages is replaced or diverted.
#
# Usage: build-debs.sh <stage dir> [output dir]
#   Versions come from the MANIFEST (Debian version + "+ilp32a64.N"); copyright and changelog from
#   Debian's (doc/glibc.*, doc/gcc-14.*).
#   STRIP  strip for ILP32 objects (default: aarch64-linux-gnu_ilp32-strip, else aarch64-linux-gnu-strip)
set -euo pipefail
umask 022
STAGE=$(realpath "${1:?usage: build-debs.sh <stage dir> [output dir]}")
OUT=$(realpath -m "${2:-out}")
T=aarch64-linux-gnu_ilp32
STRIP=${STRIP:-$(command -v $T-strip || command -v aarch64-linux-gnu-strip)}
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"
DOC=$STAGE/doc

# manifest_ver <package>: the version the MANIFEST gives for a package
manifest_ver() {
	local v
	v=$(grep -E "^ +([a-z0-9+.-]+, )*$1(, [a-z0-9+.-]+)* +[0-9][^ ,]*$" "$STAGE/MANIFEST" | head -1 | awk '{print $NF}' || true)
	[ -n "$v" ] || { echo "no version for $1 in $STAGE/MANIFEST" >&2; exit 1; }
	echo "$v"
}
GLIBC_VER=$(manifest_ver libc6-ilp32)
GCC_VER=$(manifest_ver libgcc-s1-ilp32)
GLIBC_UP=${GLIBC_VER%%-*}
GCC_UP=${GCC_VER%%-*}
echo "glibc $GLIBC_VER, GCC $GCC_VER, strip $STRIP"
for f in glibc.copyright glibc.changelog gcc-14.copyright gcc-14.changelog; do
	[ -s "$DOC/$f" ] || { echo "missing $DOC/$f" >&2; exit 1; }
done

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# strip_tree <dir>: strip shared objects like dh_strip (the dynamic linker only of debug info);
# .note.gnu.property stays, it carries the BTI marking
strip_tree() {
	local f
	while IFS= read -r -d '' f; do
		file -b "$f" | grep -q '^ELF 32-bit.*ARM aarch64' || continue
		case $f in
		*/ld-linux-aarch64_ilp32.so.1) "$STRIP" --strip-debug --remove-section=.comment "$f" ;;
		*) "$STRIP" --strip-unneeded --remove-section=.comment "$f" ;;
		esac
	done < <(find "$1" -type f -name '*.so*' -print0)
}

# debian_entry <changelog>: the first entry of Debian's changelog (the version these packages are
# built from); the full history is in Debian's source package
debian_entry() {
	awk '{ print } /^ -- / { exit }' "$1"
}

# pkg <name> <version> <source> <depends> <short> <long>: package stage/<name>; source is glibc or
# gcc-14 (Debian's copyright and changelog)
pkg() {
	local name=$1 ver=$2 src=$3 deps=$4 short=$5 long=$6 D=$W/$1
	mkdir -p "$D"
	cp -a "$STAGE/$name"/. "$D"/
	chmod -R u+rwX,go-w,go+rX "$D"
	strip_tree "$D"
	# /libilp32 -> usr/libilp32, like /lib -> usr/lib
	[ "$name" = libc6-ilp32 ] && ln -s usr/libilp32 "$D/libilp32"
	mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$name"
	cp "$DOC/$src.copyright" "$D/usr/share/doc/$name/copyright"
	{
		cat <<EOF
$name ($ver) trixie; urgency=medium

  * Debian's $src ${ver%+ilp32a64.*} built for the AArch64 ILP32 ABI
    (aarch64-linux-gnu_ilp32), installed in /usr/libilp32; see
    https://github.com/ilp32-a64/debian-ilp32 for the patches and options.

 -- $MAINT  $(LC_ALL=C TZ=UTC date -R)

EOF
		debian_entry "$DOC/$src.changelog"
	} | gzip -9n > "$D/usr/share/doc/$name/changelog.Debian.gz"
	{
		echo "Package: $name"
		echo "Source: $src-ilp32"
		echo "Version: $ver"
		echo "Architecture: arm64"
		echo "Maintainer: $MAINT"
		echo "Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)"
		[ -n "$deps" ] && echo "Depends: $deps"
		echo "Section: libs"
		echo "Priority: optional"
		echo "Homepage: https://github.com/ilp32-a64/debian-ilp32"
		echo "Description: $short"
		echo "$long" | fold -s -w 72 | sed 's/ *$//; s/^/ /'
	} > "$D/DEBIAN/control"
	(cd "$D" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z |
		xargs -0r md5sum > DEBIAN/md5sums)
	dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT/${name}_${ver}_arm64.deb" >/dev/null
	echo "built $OUT/${name}_${ver}_arm64.deb"
}

# --- libc6-ilp32 ---------------------------------------------------------------
[ -e "$STAGE/libc6-ilp32/usr/lib/ld-linux-aarch64_ilp32.so.1" ] || { echo "no dynamic linker in the tree" >&2; exit 1; }
pkg libc6-ilp32 "$GLIBC_VER" glibc "" \
	"GNU C Library: AArch64 ILP32 shared libraries" \
	"Debian's GNU C Library $GLIBC_UP for the AArch64 ILP32 ABI (32-bit pointers and long on 64-bit Arm), installed next to the system's LP64 libraries: dynamic linker /usr/lib/ld-linux-aarch64_ilp32.so.1, libraries in /usr/libilp32. Running ILP32 programs needs a kernel with ARM64_ILP32."

# --- GCC runtime libraries -------------------------------------------------------
LIBC_DEP="libc6-ilp32 (>= $GLIBC_UP)"
# gcc_pkg <package> <depends> <short description>
gcc_pkg() {
	pkg "$1" "$GCC_VER" gcc-14 "$2" "$3 (AArch64 ILP32)" \
		"$3 from Debian's gcc-14 $GCC_UP for the AArch64 ILP32 ABI, installed in /usr/libilp32 next to the system's LP64 libraries."
}
gcc_pkg libgcc-s1-ilp32 "$LIBC_DEP" "GCC support library"
gcc_pkg libstdc++6-ilp32 "$LIBC_DEP, libgcc-s1-ilp32 (>= $GCC_UP)" "GNU Standard C++ Library v3"
gcc_pkg libatomic1-ilp32 "$LIBC_DEP" "GCC support library for atomic operations"
gcc_pkg libgomp1-ilp32 "$LIBC_DEP" "GCC OpenMP (GOMP) support library"
