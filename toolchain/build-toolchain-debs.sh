#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the packages of the on-board ILP32 compiler (Debian 13 arm64 host, target
# aarch64-linux-gnu_ilp32) from install trees of Debian 13's sources, one per package
# (stage/<package>/, DESTDIR style, not stripped, with stage/MANIFEST and stage/doc/):
#   libc6-dev-ilp32                    glibc headers, crt files, static libs, linker scripts
#   linux-libc-dev-ilp32               Linux UAPI headers with the ILP32 ABI
#   binutils-aarch64-linux-gnu-ilp32   Debian's binutils
#   gcc-14-aarch64-linux-gnu-ilp32     Debian's gcc-14: C compiler and target dev files
#   g++-14-aarch64-linux-gnu-ilp32     the C++ compiler and libstdc++ dev files
# plus the metapackages gcc-aarch64-linux-gnu-ilp32 and g++-aarch64-linux-gnu-ilp32, which own
# the unversioned command names (aarch64-linux-gnu_ilp32-gcc -> ...-gcc-14), as Debian does.
# The compiler trees may come from another stage dir (built on an arm64 machine); packages whose
# tree is missing are skipped.
# Usage: build-toolchain-debs.sh <stage dir> [output dir]
#   CC_STAGE  stage dir of binutils, gcc-14 and g++-14 (default: the stage dir)
#   ONLY      "compiler": only gcc-14, g++-14 and their metapackages (a compiler rebuilt against
#             released dev and runtime packages, which must not be packaged again)
set -euo pipefail
umask 022
STAGE=$(realpath "${1:?usage: build-toolchain-debs.sh <stage dir> [output dir]}")
CC_STAGE=$(realpath "${CC_STAGE:-$STAGE}")
OUT=$(realpath -m "${2:-out}")
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"
T=aarch64-linux-gnu_ilp32
STRIP32=${STRIP32:-$(command -v $T-strip || command -v aarch64-linux-gnu-strip)}
STRIP64=${STRIP64:-$(command -v aarch64-linux-gnu-strip || command -v strip)}

# manifest_ver <stage dir> <package>: the version the MANIFEST gives for a package
manifest_ver() {
	grep -E "^ +([a-z0-9+.-]+, )*$2(,| )" "$1/MANIFEST" 2>/dev/null | head -1 | awk '{print $NF}'
}
need() { [ -n "$2" ] || { echo "no version for $1 in the MANIFEST" >&2; exit 1; }; echo "$2"; }
GLIBC_VER=$(need libc6-dev-ilp32 "$(manifest_ver "$STAGE" libc6-dev-ilp32)")
KVER=$(need linux-libc-dev-ilp32 "$(manifest_ver "$STAGE" linux-libc-dev-ilp32)")
GCC_VER=$(manifest_ver "$CC_STAGE" gcc-14-aarch64-linux-gnu-ilp32)
GCC_VER=${GCC_VER:-$(need libgcc-s1-ilp32 "$(manifest_ver "$STAGE" libgcc-s1-ilp32)")}
# The GCC runtime packages the compiler goes with (a "runtime: <version>" line in the compiler's
# MANIFEST when the compiler was rebuilt alone)
RT_VER=$(sed -n 's/^ *runtime: *\([^ ]*\).*/\1/p' "$CC_STAGE/MANIFEST" | head -1)
RT_VER=${RT_VER:-$(need libgcc-s1-ilp32 "$(manifest_ver "$STAGE" libgcc-s1-ilp32)")}
BIN_VER=$(manifest_ver "$CC_STAGE" binutils-aarch64-linux-gnu-ilp32)
KCOMMIT=$(grep -o 'linux-ilp32 ilp32-6.12.y [0-9a-f]*' "$STAGE/MANIFEST" | awk '{print $3}')
echo "glibc $GLIBC_VER, linux $KVER ($KCOMMIT), gcc $GCC_VER (runtime $RT_VER), binutils ${BIN_VER:-none}"
# The runtime packages the dev files must match exactly
RT="libc6-ilp32 (= $GLIBC_VER)"
GRT="libgcc-s1-ilp32 (= $RT_VER), libatomic1-ilp32 (= $RT_VER), libgomp1-ilp32 (= $RT_VER)"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# host_dep <tree>: the Depends of the host (LP64) binaries in the tree, from their NEEDED entries:
# "libc6 (>= <highest GLIBC symbol version>)" and the Debian 13 package of every other library
# that the tree does not have itself
host_dep() {
	local bins v so own deps=()
	bins=$(find "$1" -type f -exec sh -c 'file -b "$1" | grep -q "^ELF 64-bit.*ARM aarch64" && echo "$1"' _ {} \;)
	v=$(echo "$bins" | xargs -r readelf -W --dyn-syms 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -Vu | tail -1)
	deps+=("libc6 (>= ${v:-2.17})")
	own=$(find "$1" -name '*.so*' -printf '%f\n')
	for so in $(echo "$bins" | xargs -r readelf -d 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u); do
		echo "$own" | grep -qxF "$so" && continue
		case $so in
		libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | ld-linux-aarch64.so.1) ;;
		libgcc_s.so.1) deps+=(libgcc-s1) ;;
		libstdc++.so.6) deps+=(libstdc++6) ;;
		libgmp.so.10) deps+=(libgmp10) ;;
		libisl.so.23) deps+=(libisl23) ;;
		libjansson.so.4) deps+=(libjansson4) ;;
		libmpc.so.3) deps+=(libmpc3) ;;
		libmpfr.so.6) deps+=(libmpfr6) ;;
		libz.so.1) deps+=(zlib1g) ;;
		libzstd.so.1) deps+=(libzstd1) ;;
		*) echo "host_dep: no package known for $so" >&2; exit 1 ;;
		esac
	done
	(IFS=,; echo "${deps[*]}" | sed 's/,/, /g')
}

# strip_tree <dir>: like dh_strip: host (LP64) programs and shared objects --strip-unneeded,
# ILP32 shared objects --strip-unneeded, ILP32 static libraries and objects --strip-debug;
# .note.gnu.property stays, it carries the BTI marking
strip_tree() {
	local f t
	while IFS= read -r -d '' f; do
		t=$(file -b "$f")
		case $t in
		"ELF 64-bit"*"ARM aarch64"*) "$STRIP64" --strip-unneeded --remove-section=.comment "$f" ;;
		"ELF 32-bit"*"ARM aarch64"*"shared object"*) "$STRIP32" --strip-unneeded --remove-section=.comment "$f" ;;
		"ELF 32-bit"*"ARM aarch64"*"relocatable"*) "$STRIP32" --strip-debug "$f" ;;
		"current ar archive"*)
			case $f in *.a) "$STRIP32" --strip-debug "$f" 2>/dev/null || "$STRIP64" --strip-debug "$f" ;; esac ;;
		esac
	done < <(find "$1" -type f -print0)
}

# copyright <source>: Debian's copyright file of the source, ours for linux and the metapackages
copyright() {
	case $1 in
	glibc | gcc-14 | binutils) cat "$STAGE/doc/$1.copyright" ;;
	linux)
		printf 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\nUpstream-Name: Linux (AArch64 ILP32)\nSource: https://github.com/ilp32-a64/linux-ilp32 (branch ilp32-6.12.y, commit %s)\n\nFiles: *\nCopyright: Linus Torvalds and others\nLicense: GPL-2 WITH Linux-syscall-note\n On Debian systems, the full text of the GNU General Public License version 2\n can be found in /usr/share/common-licenses/GPL-2.\n' "$KCOMMIT" ;;
	mit)
		printf 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\nUpstream-Name: debian-ilp32\nSource: https://github.com/ilp32-a64/debian-ilp32\n\nFiles: *\nCopyright: 2026 liviyifan\nLicense: MIT\n See https://github.com/ilp32-a64/debian-ilp32/blob/main/LICENSE\n' ;;
	esac
}

# debian_entry <changelog>: the first entry of Debian's changelog (the version these packages are
# built from); the full history is in Debian's source package
debian_entry() {
	awk '{ print } /^ -- / { exit }' "$1"
}

# pkg <name> <version> <arch> <section> <source> <depends> <short> <long> [tree]
pkg() {
	local name=$1 ver=$2 arch=$3 section=$4 src=$5 deps=$6 short=$7 long=$8 tree=${9:-} D=$W/$1
	mkdir -p "$D"
	if [ -n "$tree" ]; then
		cp -a "$tree"/. "$D"/
		chmod -R u+rwX,go-w,go+rX "$D"
		strip_tree "$D"
	fi
	mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$name"
	copyright "$src" > "$D/usr/share/doc/$name/copyright"
	{
		cat <<EOF
$name ($ver) trixie; urgency=medium

  * Built for the AArch64 ILP32 ABI (aarch64-linux-gnu_ilp32) on Debian 13 arm64;
    see https://github.com/ilp32-a64/debian-ilp32 for the patches and options.

 -- $MAINT  $(LC_ALL=C TZ=UTC date -R)
EOF
		case $src in glibc | gcc-14 | binutils) echo; debian_entry "$STAGE/doc/$src.changelog" ;; esac
	} | gzip -9n > "$D/usr/share/doc/$name/changelog.Debian.gz"
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

if [ "${ONLY:-}" != compiler ]; then
pkg linux-libc-dev-ilp32 "$KVER" all devel linux "" \
	"Linux UAPI headers for AArch64 ILP32" \
	"Linux kernel headers for user space with the AArch64 ILP32 ABI, in /usr/$T/include, for the aarch64-linux-gnu_ilp32 compiler." \
	"$STAGE/linux-libc-dev-ilp32"
pkg libc6-dev-ilp32 "$GLIBC_VER" arm64 libdevel glibc "$RT, linux-libc-dev-ilp32 (= $KVER)" \
	"GNU C Library: AArch64 ILP32 development files" \
	"Headers (/usr/$T/include), crt files, static libraries and linker scripts (/usr/libilp32) of Debian's glibc to build programs for the AArch64 ILP32 ABI against libc6-ilp32." \
	"$STAGE/libc6-dev-ilp32"
fi

if [ ! -d "$CC_STAGE/gcc-14-aarch64-linux-gnu-ilp32" ]; then
	echo "no compiler trees in $CC_STAGE: binutils, gcc and g++ packages skipped"
	exit 0
fi
# binutils from the compiler's stage dir; with ONLY=compiler the compiler depends on the released one
BIN_VER=${BIN_VER:-$(manifest_ver "$STAGE" binutils-aarch64-linux-gnu-ilp32)}
[ -n "$BIN_VER" ] || { echo "no binutils version in the MANIFESTs" >&2; exit 1; }
# (assignments, so that a library without a known package stops the build)
GCC_DEP=$(host_dep "$CC_STAGE/gcc-14-aarch64-linux-gnu-ilp32")
GXX_DEP=$(host_dep "$CC_STAGE/g++-14-aarch64-linux-gnu-ilp32")
if [ "${ONLY:-}" != compiler ]; then
BIN_DEP=$(host_dep "$CC_STAGE/binutils-aarch64-linux-gnu-ilp32")
pkg binutils-aarch64-linux-gnu-ilp32 "$BIN_VER" arm64 devel binutils "$BIN_DEP" \
	"GNU binary utilities for AArch64 ILP32" \
	"Debian's GNU assembler, linker and binary utilities for the AArch64 ILP32 ABI, named $T-as, $T-ld and so on." \
	"$CC_STAGE/binutils-aarch64-linux-gnu-ilp32"
fi
pkg gcc-14-aarch64-linux-gnu-ilp32 "$GCC_VER" arm64 devel gcc-14 \
	"$GCC_DEP, binutils-aarch64-linux-gnu-ilp32 (>= $BIN_VER), libc6-dev-ilp32 (= $GLIBC_VER), $GRT" \
	"GNU C compiler 14 for AArch64 ILP32" \
	"Debian's GCC 14 for the AArch64 ILP32 ABI ($T-gcc-14), running on Debian 13 arm64. Programs it builds use the ILP32 runtime in /usr/libilp32 and run on a kernel with the ILP32 ABI." \
	"$CC_STAGE/gcc-14-aarch64-linux-gnu-ilp32"
pkg g++-14-aarch64-linux-gnu-ilp32 "$GCC_VER" arm64 devel gcc-14 \
	"$GXX_DEP, gcc-14-aarch64-linux-gnu-ilp32 (= $GCC_VER), libstdc++6-ilp32 (= $RT_VER)" \
	"GNU C++ compiler 14 for AArch64 ILP32" \
	"Debian's G++ 14 for the AArch64 ILP32 ABI ($T-g++-14) and the libstdc++ development files." \
	"$CC_STAGE/g++-14-aarch64-linux-gnu-ilp32"

# Metapackages with the unversioned command names
mkdir -p "$W/meta-gcc/usr/bin" "$W/meta-g++/usr/bin"
for f in "$CC_STAGE"/gcc-14-aarch64-linux-gnu-ilp32/usr/bin/$T-*-14; do
	b=$(basename "$f")
	ln -s "$b" "$W/meta-gcc/usr/bin/${b%-14}"
done
ln -s $T-g++-14 "$W/meta-g++/usr/bin/$T-g++"
pkg gcc-aarch64-linux-gnu-ilp32 "$GCC_VER" arm64 devel mit "gcc-14-aarch64-linux-gnu-ilp32 (>= $GCC_VER)" \
	"GNU C compiler for AArch64 ILP32 (default version)" \
	"Depends on the default GCC version for the AArch64 ILP32 ABI and provides the unversioned command names: $T-gcc, $T-cpp and so on." \
	"$W/meta-gcc"
pkg g++-aarch64-linux-gnu-ilp32 "$GCC_VER" arm64 devel mit \
	"g++-14-aarch64-linux-gnu-ilp32 (>= $GCC_VER), gcc-aarch64-linux-gnu-ilp32 (= $GCC_VER)" \
	"GNU C++ compiler for AArch64 ILP32 (default version)" \
	"Depends on the default G++ version for the AArch64 ILP32 ABI and provides $T-g++." \
	"$W/meta-g++"
