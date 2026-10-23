#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the metapackages. The kernel and the ILP32 runtime are installed separately, so that a
# system can keep its own ILP32 kernel (another board, a self-built kernel):
#   ilp32-runtime             depends on the five ILP32 runtime packages and the keyring;
#                             suggests linux-image-ilp32-arm64
#   linux-image-ilp32-arm64   depends on the current linux-image-<release>, so that "apt upgrade"
#                             follows new kernel versions (which come with new package names);
#                             named like Debian's linux-image-<featureset>-<arch> (linux-image-rt-arm64)
#   linux-headers-ilp32-arm64 depends on the current linux-headers-<release>
# The kernel release and version are taken from the linux-image package in the kernel debs dir.
# Usage: build-meta-debs.sh <kernel debs dir> [output dir]
#   VERSION  version of ilp32-runtime (default: today, e.g. 2026.10.24)
#   REV      revision of the kernel metapackages (default 1)
set -euo pipefail
umask 022
KDEBS=$(realpath "${1:?usage: build-meta-debs.sh <kernel debs dir> [output dir]}")
OUT=$(realpath -m "${2:-out}")
VERSION=${VERSION:-$(date +%Y.%m.%d)}
REV=${REV:-1}
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"
FLAVOUR=ilp32-arm64

KIMG=$(ls "$KDEBS"/linux-image-*-"$FLAVOUR"_*.deb | grep -v -e -dbg_ -e "linux-image-${FLAVOUR}_" | head -1)
KPKG=$(dpkg-deb -f "$KIMG" Package)
KVER=$(dpkg-deb -f "$KIMG" Version)
KREL=${KPKG#linux-image-}
HPKG=linux-headers-$KREL
# The metapackage version follows the kernel: 6.12.114-ilp32-arm64 -> 6.12.114+ilp32a64.1
MVER=${KREL%-"$FLAVOUR"}+ilp32a64.$REV
echo "kernel $KPKG $KVER -> metapackages $MVER, ilp32-runtime $VERSION"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# meta <package> <version> <section> <depends> <suggests> <short> <long>
meta() {
	local name=$1 ver=$2 section=$3 deps=$4 suggests=$5 short=$6 long=$7 D=$W/$1
	mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$name"
	cat <<EOF | gzip -9n > "$D/usr/share/doc/$name/changelog.Debian.gz"
$name ($ver) trixie; urgency=medium

  * Depends: $deps

 -- $MAINT  $(LC_ALL=C TZ=UTC date -R)
EOF
	cat > "$D/usr/share/doc/$name/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: debian-ilp32
Source: https://github.com/ilp32-a64/debian-ilp32

Files: *
Copyright: 2026 liviyifan
License: MIT
 See https://github.com/ilp32-a64/debian-ilp32/blob/main/LICENSE
EOF
	{
		echo "Package: $name"
		echo "Version: $ver"
		echo "Architecture: arm64"
		echo "Maintainer: $MAINT"
		echo "Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)"
		echo "Depends: $deps"
		[ -n "$suggests" ] && echo "Suggests: $suggests"
		echo "Section: $section"
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

meta "linux-image-$FLAVOUR" "$MVER" kernel "$KPKG (= $KVER)" "" \
	"Linux kernel with AArch64 ILP32 support (latest)" \
	"Depends on the latest kernel with the AArch64 ILP32 ABI from the ILP32-A64 repository, so that apt upgrade installs new kernel versions."
meta "linux-headers-$FLAVOUR" "$MVER" kernel "$HPKG (= $KVER)" "" \
	"Headers for the Linux kernel with AArch64 ILP32 support (latest)" \
	"Depends on the headers of the latest kernel with the AArch64 ILP32 ABI from the ILP32-A64 repository."
meta ilp32-runtime "$VERSION" metapackages \
	"libc6-ilp32, libgcc-s1-ilp32, libstdc++6-ilp32, libatomic1-ilp32, libgomp1-ilp32, ilp32-a64-archive-keyring" \
	"linux-image-$FLAVOUR" \
	"AArch64 ILP32 runtime libraries" \
	"Installs the AArch64 ILP32 runtime libraries (glibc, libgcc_s, libstdc++, libatomic, libgomp) next to the system's 64-bit libraries. Running ILP32 programs needs a kernel with the ILP32 ABI, such as linux-image-$FLAVOUR; it is not installed by this package."
