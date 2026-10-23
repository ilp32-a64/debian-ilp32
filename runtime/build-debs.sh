#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the ILP32 runtime packages (biarch, Architecture: arm64) from an installed
# AArch64 ILP32 glibc toolchain. The packages install next to Debian's own LP64 libraries:
#   dynamic linker  /usr/lib/ld-linux-aarch64_ilp32.so.1   (PT_INTERP /lib/... via merged /usr)
#   libraries       /usr/libilp32                          (/libilp32 -> usr/libilp32)
# Nothing of Debian's own packages is replaced or diverted.
#
# Usage: build-debs.sh [output dir]
#   TC         toolchain prefix (default ~/work/ilp32-glibc/toolchain/out)
#   GLIBC_SRC  glibc source tree, for the license files (default ~/work/glibc-ilp32-2.41)
#   GCC_SRC    GCC source tree, for the license files (default $TC/../src/gcc-14.3.0)
#   REV        Debian revision of all packages (default 1+ilp32a64.1; the +ilp32a64 suffix keeps
#              them apart from versions of Debian's own packages)
set -euo pipefail
umask 022
TC=${TC:-$HOME/work/ilp32-glibc/toolchain/out}
GLIBC_SRC=${GLIBC_SRC:-$HOME/work/glibc-ilp32-2.41}
GCC_SRC=${GCC_SRC:-$(realpath "$TC/../src/gcc-14.3.0")}
REV=${REV:-1+ilp32a64.1}
OUT=$(realpath -m "${1:-out}")
T=aarch64-linux-gnu_ilp32
SYSROOT=$TC/$T/sysroot
GCCLIB=$TC/$T/libilp32
STRIP=$TC/bin/$T-strip
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"

GLIBC_VER=$(strings "$SYSROOT/libilp32/libc.so.6" |
	sed -n 's/^GNU C Library .* version \([0-9.]*[0-9]\)\.*$/\1/p' | head -1)
[ -n "$GLIBC_VER" ] || { echo "cannot find the glibc version" >&2; exit 1; }
GCC_VER=$("$TC/bin/$T-gcc" -dumpversion)
echo "glibc $GLIBC_VER, GCC $GCC_VER"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# pkg_begin <name>: start a package tree in $D
pkg_begin() {
	D=$W/$1
	mkdir -p "$D/DEBIAN" "$D/usr/libilp32" "$D/usr/share/doc/$1"
}

# pkg_end <name> <version> <depends> <description> <long description>
pkg_end() {
	local name=$1 ver=$2 deps=$3 short=$4 long=$5
	gzip -9n < "$W/changelog" > "$D/usr/share/doc/$name/changelog.Debian.gz"
	{
		echo "Package: $name"
		echo "Version: $ver"
		echo "Architecture: arm64"
		echo "Maintainer: $MAINT"
		echo "Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)"
		[ -n "$deps" ] && echo "Depends: $deps"
		echo "Section: libs"
		echo "Priority: optional"
		echo "Homepage: https://github.com/ilp32-a64"
		echo "Description: $short"
		echo "$long" | fold -s -w 72 | sed 's/ *$//; s/^/ /'
	} > "$D/DEBIAN/control"
	(cd "$D" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z |
		xargs -0r md5sum > DEBIAN/md5sums)
	dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT/${name}_${ver}_arm64.deb" >/dev/null
	echo "built $OUT/${name}_${ver}_arm64.deb"
}

# copy_lib <file> <dest dir>: copy a shared library and strip it
copy_lib() {
	install -m 0644 "$1" "$2/"
	# Keep the notes: .note.gnu.property carries the BTI/PAC marking.
	"$STRIP" --strip-unneeded --remove-section=.comment "$2/$(basename "$1")"
}

cat > "$W/changelog" <<EOF
ilp32-runtime-libs ($REV) unstable; urgency=medium

  * Built from glibc $GLIBC_VER (ILP32 port) and GCC $GCC_VER.

 -- $MAINT  $(date -R)
EOF

lgpl_copyright() {
	cat <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: GNU C Library (AArch64 ILP32 port)
Source: https://github.com/ilp32-a64/glibc-ilp32 (branch ilp32-$GLIBC_VER)

Files: *
Copyright: Free Software Foundation, Inc. and the glibc contributors
License: LGPL-2.1+
 On Debian systems, the full text of the GNU Lesser General Public License
 version 2.1 can be found in /usr/share/common-licenses/LGPL-2.1.
 Some parts are under other free licenses; see the file LICENSES in the
 source tree.
EOF
}

gcc_copyright() {
	cat <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: GCC runtime libraries
Source: https://gcc.gnu.org/ (GCC $GCC_VER)

Files: *
Copyright: Free Software Foundation, Inc.
License: GPL-3+ with GCC-Runtime-Library-Exception-3.1
 On Debian systems, the full text of the GNU General Public License
 version 3 can be found in /usr/share/common-licenses/GPL-3.
 The GCC Runtime Library Exception, version 3.1, follows.
 .
EOF
	sed 's/^$/./; s/^/ /' "$GCC_SRC/COPYING.RUNTIME"
}

# --- libc6-ilp32 ---------------------------------------------------------------
pkg_begin libc6-ilp32
mkdir -p "$D/usr/lib" "$D/usr/libilp32/gconv"
install -m 0755 "$SYSROOT/lib/ld-linux-aarch64_ilp32.so.1" "$D/usr/lib/"
"$STRIP" --strip-debug "$D/usr/lib/ld-linux-aarch64_ilp32.so.1"
for f in "$SYSROOT"/libilp32/*.so*; do copy_lib "$f" "$D/usr/libilp32"; done
for f in "$SYSROOT"/usr/libilp32/gconv/*.so; do copy_lib "$f" "$D/usr/libilp32/gconv"; done
cp -a "$SYSROOT"/usr/libilp32/gconv/gconv-modules* "$D/usr/libilp32/gconv/"
ln -s usr/libilp32 "$D/libilp32"
lgpl_copyright > "$D/usr/share/doc/libc6-ilp32/copyright"
pkg_end libc6-ilp32 "$GLIBC_VER-$REV" "" \
	"GNU C Library: AArch64 ILP32 shared libraries" \
	"The GNU C Library for the AArch64 ILP32 ABI (32-bit pointers and long on 64-bit Arm), installed next to the system's LP64 libraries: dynamic linker /usr/lib/ld-linux-aarch64_ilp32.so.1, libraries in /usr/libilp32. Running ILP32 programs needs a kernel with ARM64_ILP32."

# --- GCC runtime libraries -------------------------------------------------------
# gcc_pkg <package> <soname file> <depends> <short description>
gcc_pkg() {
	local name=$1 lib=$2 deps=$3 short=$4 real
	pkg_begin "$name"
	real=$(readlink -f "$GCCLIB/$lib")
	copy_lib "$real" "$D/usr/libilp32"
	[ "$(basename "$real")" != "$lib" ] && ln -s "$(basename "$real")" "$D/usr/libilp32/$lib"
	gcc_copyright > "$D/usr/share/doc/$name/copyright"
	pkg_end "$name" "$GCC_VER-$REV" "$deps" "$short (AArch64 ILP32)" \
		"$short for the AArch64 ILP32 ABI, installed in /usr/libilp32 next to the system's LP64 libraries."
}
LIBC_DEP="libc6-ilp32 (>= $GLIBC_VER)"
gcc_pkg libgcc-s1-ilp32 libgcc_s.so.1 "$LIBC_DEP" "GCC support library"
gcc_pkg libstdc++6-ilp32 libstdc++.so.6 "$LIBC_DEP, libgcc-s1-ilp32 (>= $GCC_VER)" "GNU Standard C++ Library v3"
gcc_pkg libatomic1-ilp32 libatomic.so.1 "$LIBC_DEP" "GCC support library for atomic operations"
gcc_pkg libgomp1-ilp32 libgomp.so.1 "$LIBC_DEP" "GCC OpenMP (GOMP) support library"
