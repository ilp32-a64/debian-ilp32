#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the packages of the on-board ILP32 compiler (Debian 13 arm64 host, target
# aarch64-linux-gnu_ilp32) from install trees, one per package (stage/<package>/, DESTDIR style):
#   binutils-aarch64-linux-gnu-ilp32   binutils 2.44
#   gcc-14-aarch64-linux-gnu-ilp32     GCC 14.3 C compiler and target dev files
#   g++-14-aarch64-linux-gnu-ilp32     the C++ compiler and libstdc++ dev files
#   libc6-dev-ilp32                    glibc 2.41 headers, crt files, static libs, linker scripts
#   linux-libc-dev-ilp32               Linux UAPI headers with the ILP32 ABI
# plus the metapackages gcc-aarch64-linux-gnu-ilp32 and g++-aarch64-linux-gnu-ilp32, which own
# the unversioned command names (aarch64-linux-gnu_ilp32-gcc -> ...-gcc-14), as Debian does.
# Usage: build-toolchain-debs.sh <stage dir> [output dir]
#   REV  Debian revision of all packages (default 1+ilp32a64.1)
set -euo pipefail
umask 022
STAGE=$(realpath "${1:?usage: build-toolchain-debs.sh <stage dir> [output dir]}")
OUT=$(realpath -m "${2:-out}")
REV=${REV:-1+ilp32a64.1}
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"
T=aarch64-linux-gnu_ilp32
GCCV=14.3.0
BINV=2.44
GLIBCV=2.41
KV=6.12.114
# The runtime packages the dev files must match exactly
RT="libc6-ilp32 (= $GLIBCV-$REV)"
GRT="libgcc-s1-ilp32 (= $GCCV-$REV), libatomic1-ilp32 (= $GCCV-$REV), libgomp1-ilp32 (= $GCCV-$REV)"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# host_dep <tree>: "libc6 (>= <highest GLIBC symbol version>)" for the host binaries in the tree
host_dep() {
	local v
	v=$(find "$1" -type f -exec sh -c 'file -b "$1" | grep -q "^ELF 64-bit.*ARM aarch64" && echo "$1"' _ {} \; |
		xargs -r readelf -W --dyn-syms 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -Vu | tail -1)
	echo "libc6 (>= ${v:-2.17})"
}

# copyright <license id>: a copyright file for the license
copyright() {
	echo "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/"
	case $1 in
	binutils)
		printf 'Upstream-Name: GNU Binutils\nSource: https://ftp.gnu.org/gnu/binutils/binutils-%s.tar.xz\n\nFiles: *\nCopyright: Free Software Foundation, Inc.\nLicense: GPL-3+\n On Debian systems, the full text of the GNU General Public License version 3\n can be found in /usr/share/common-licenses/GPL-3.\n' $BINV ;;
	gcc)
		printf 'Upstream-Name: GCC\nSource: https://ftp.gnu.org/gnu/gcc/gcc-%s/ with the patches in\n https://github.com/ilp32-a64/test-ilp32 (glibc/toolchain/patches/gcc-%s)\n\nFiles: *\nCopyright: Free Software Foundation, Inc.\nLicense: GPL-3+ with GCC-Runtime-Library-Exception-3.1\n On Debian systems, the full text of the GNU General Public License version 3\n can be found in /usr/share/common-licenses/GPL-3. Target libraries are under\n the GCC Runtime Library Exception, version 3.1.\n' $GCCV $GCCV ;;
	glibc)
		printf 'Upstream-Name: GNU C Library (AArch64 ILP32 port)\nSource: https://github.com/ilp32-a64/glibc-ilp32 (branch ilp32-%s)\n\nFiles: *\nCopyright: Free Software Foundation, Inc. and the glibc contributors\nLicense: LGPL-2.1+\n On Debian systems, the full text of the GNU Lesser General Public License\n version 2.1 can be found in /usr/share/common-licenses/LGPL-2.1.\n' $GLIBCV ;;
	linux)
		printf 'Upstream-Name: Linux (AArch64 ILP32)\nSource: https://github.com/ilp32-a64/linux-ilp32 (branch ilp32-6.12.y, commit 3cf855b379)\n\nFiles: *\nCopyright: Linus Torvalds and others\nLicense: GPL-2 WITH Linux-syscall-note\n On Debian systems, the full text of the GNU General Public License version 2\n can be found in /usr/share/common-licenses/GPL-2.\n' ;;
	mit)
		printf 'Upstream-Name: debian-ilp32\nSource: https://github.com/ilp32-a64/debian-ilp32\n\nFiles: *\nCopyright: 2026 liviyifan\nLicense: MIT\n See https://github.com/ilp32-a64/debian-ilp32/blob/main/LICENSE\n' ;;
	esac
}

# pkg <name> <version> <arch> <section> <license> <depends> <short> <long> [tree]
pkg() {
	local name=$1 ver=$2 arch=$3 section=$4 lic=$5 deps=$6 short=$7 long=$8 tree=${9:-} D=$W/$1
	mkdir -p "$D"
	if [ -n "$tree" ]; then
		cp -a "$tree"/. "$D"/
		chmod -R u+rwX,go-w,go+rX "$D"
	fi
	mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$name"
	copyright "$lic" > "$D/usr/share/doc/$name/copyright"
	cat <<EOF | gzip -9n > "$D/usr/share/doc/$name/changelog.Debian.gz"
$name ($ver) trixie; urgency=medium

  * Built for the AArch64 ILP32 ABI (aarch64-linux-gnu_ilp32) on Debian 13 arm64.

 -- $MAINT  $(LC_ALL=C TZ=UTC date -R)
EOF
	{
		echo "Package: $name"
		echo "Version: $ver"
		echo "Architecture: $arch"
		echo "Maintainer: $MAINT"
		echo "Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)"
		[ -n "$deps" ] && echo "Depends: $deps"
		echo "Section: $section"
		echo "Priority: optional"
		echo "Homepage: https://github.com/ilp32-a64/debian-ilp32"
		echo "Description: $short"
		echo "$long" | fold -s -w 72 | sed 's/ *$//; s/^/ /'
	} > "$D/DEBIAN/control"
	(cd "$D" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z |
		xargs -0r md5sum > DEBIAN/md5sums)
	dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT/${name}_${ver}_$arch.deb" >/dev/null
	echo "built $OUT/${name}_${ver}_$arch.deb"
}

pkg linux-libc-dev-ilp32 "$KV-$REV" all devel linux "" \
	"Linux UAPI headers for AArch64 ILP32" \
	"Linux kernel headers for user space with the AArch64 ILP32 ABI, in /usr/$T/include, for the aarch64-linux-gnu_ilp32 compiler." \
	"$STAGE/linux-libc-dev-ilp32"
pkg libc6-dev-ilp32 "$GLIBCV-$REV" arm64 libdevel glibc "$RT, linux-libc-dev-ilp32 (= $KV-$REV)" \
	"GNU C Library: AArch64 ILP32 development files" \
	"Headers (/usr/$T/include), crt files, static libraries and linker scripts (/usr/libilp32) to build programs for the AArch64 ILP32 ABI against libc6-ilp32." \
	"$STAGE/libc6-dev-ilp32"
pkg binutils-aarch64-linux-gnu-ilp32 "$BINV-$REV" arm64 devel binutils "$(host_dep "$STAGE/binutils-aarch64-linux-gnu-ilp32")" \
	"GNU binary utilities for AArch64 ILP32" \
	"The GNU assembler, linker and binary utilities for the AArch64 ILP32 ABI, named $T-as, $T-ld and so on." \
	"$STAGE/binutils-aarch64-linux-gnu-ilp32"
pkg gcc-14-aarch64-linux-gnu-ilp32 "$GCCV-$REV" arm64 devel gcc \
	"$(host_dep "$STAGE/gcc-14-aarch64-linux-gnu-ilp32"), binutils-aarch64-linux-gnu-ilp32 (>= $BINV-$REV), libc6-dev-ilp32 (= $GLIBCV-$REV), $GRT" \
	"GNU C compiler 14 for AArch64 ILP32" \
	"GCC 14.3 for the AArch64 ILP32 ABI ($T-gcc-14), running on Debian 13 arm64. Programs it builds use the ILP32 runtime in /usr/libilp32 and run on a kernel with the ILP32 ABI." \
	"$STAGE/gcc-14-aarch64-linux-gnu-ilp32"
pkg g++-14-aarch64-linux-gnu-ilp32 "$GCCV-$REV" arm64 devel gcc \
	"$(host_dep "$STAGE/g++-14-aarch64-linux-gnu-ilp32"), gcc-14-aarch64-linux-gnu-ilp32 (= $GCCV-$REV), libstdc++6-ilp32 (= $GCCV-$REV)" \
	"GNU C++ compiler 14 for AArch64 ILP32" \
	"G++ 14.3 for the AArch64 ILP32 ABI ($T-g++-14) and the libstdc++ development files." \
	"$STAGE/g++-14-aarch64-linux-gnu-ilp32"

# Metapackages with the unversioned command names
mkdir -p "$W/meta-gcc/usr/bin" "$W/meta-g++/usr/bin"
for f in "$STAGE"/gcc-14-aarch64-linux-gnu-ilp32/usr/bin/$T-*-14; do
	b=$(basename "$f")
	ln -s "$b" "$W/meta-gcc/usr/bin/${b%-14}"
done
ln -s $T-g++-14 "$W/meta-g++/usr/bin/$T-g++"
pkg gcc-aarch64-linux-gnu-ilp32 "$GCCV-$REV" arm64 devel mit "gcc-14-aarch64-linux-gnu-ilp32 (>= $GCCV-$REV)" \
	"GNU C compiler for AArch64 ILP32 (default version)" \
	"Depends on the default GCC version for the AArch64 ILP32 ABI and provides the unversioned command names: $T-gcc, $T-cpp and so on." \
	"$W/meta-gcc"
pkg g++-aarch64-linux-gnu-ilp32 "$GCCV-$REV" arm64 devel mit \
	"g++-14-aarch64-linux-gnu-ilp32 (>= $GCCV-$REV), gcc-aarch64-linux-gnu-ilp32 (= $GCCV-$REV)" \
	"GNU C++ compiler for AArch64 ILP32 (default version)" \
	"Depends on the default G++ version for the AArch64 ILP32 ABI and provides $T-g++." \
	"$W/meta-g++"
