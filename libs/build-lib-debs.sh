#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the ILP32 packages of one Debian 13 source library (zlib, openssl, python3.13, ...) from a
# snapshot of install trees: <snapshot>/<package>/ (DESTDIR style, not stripped), <snapshot>/MANIFEST
# and <snapshot>/doc/<source>.{copyright,changelog}. The MANIFEST gives
#   versions:      "  <pkg>, <pkg>  <version>"
#   packages:      "  <pkg>  section=<section>  desc=<short description>  source=<source>"
#   dev-depends:   "  <pkg>  <dep>, <dep>"        (the -dev packages' Depends besides their libraries)
# Runtime packages depend on the -ilp32 packages that ship the sonames their ELF objects need
# (>= the upstream version), found in the .debs of the dirs given; a -dev package depends on the
# runtime packages of its source at the exact version.
# Usage: build-lib-debs.sh <snapshot> <output dir> <dir with .debs>...
#   STRIP  strip for ILP32 objects (default: aarch64-linux-gnu_ilp32-strip, else aarch64-linux-gnu-strip)
set -euo pipefail
umask 022
SNAP=$(realpath "${1:?usage: build-lib-debs.sh <snapshot> <output dir> <dir with .debs>...}")
OUT=$(realpath -m "${2:?output dir}")
shift 2
T=aarch64-linux-gnu_ilp32
STRIP=${STRIP:-$(command -v $T-strip || command -v aarch64-linux-gnu-strip)}
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"
M=$SNAP/MANIFEST

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# block <name>: the indented lines of a MANIFEST block ("name:" up to the next blank line)
block() { awk -v b="$1:" '$0 == b { on = 1; next } on && /^$/ { exit } on' "$M"; }

# version <pkg>
version() {
	local re=${1//+/\\+}
	block versions | grep -E "^ +([a-z0-9+.-]+, )*$re(, [a-z0-9+.-]+)* +[0-9][^ ,]*$" |
		awk '{print $NF}' | head -1
}
# field <pkg> <key>: a key=value field of the packages block (values may contain spaces)
field() {
	block packages | awk -v p="$1" -v k="$2" '$1 == p {
		s = $0; i = index(s, "  " k "="); if (!i) exit
		s = substr(s, i + length(k) + 3); j = index(s, "  "); print (j ? substr(s, 1, j - 1) : s); exit }'
}
PKGS=$(block packages | awk '{print $1}')
[ -n "$PKGS" ] || { echo "no packages block in $M" >&2; exit 1; }

# The sonames of the given .debs and of this snapshot's runtime packages: "<file> <package> <version>"
for d in "$@"; do
	for deb in "$d"/*.deb; do
		[ -e "$deb" ] || continue
		p=$(dpkg-deb -f "$deb" Package)
		v=$(dpkg-deb -f "$deb" Version)
		dpkg-deb -c "$deb" | awk '{print $6}' | { grep -E '^\./usr/(libilp32/[^/]+\.so\.[0-9]|lib/ld-linux-aarch64_ilp32\.so\.1$)' || true; } |
			sed "s|.*/||; s|\$| $p $v|"
	done
done | sort -u > "$W/sonames"
for p in $PKGS; do
	case $p in *-dev-ilp32) continue ;; esac
	find "$SNAP/$p" \( -type f -o -type l \) -name '*.so.[0-9]*' -printf "%f $p $(version "$p")\n"
done | sort -u >> "$W/sonames"

# shlib_deps <tree> <own source>: the Depends of the ELF32 objects in the tree
shlib_deps() {
	local f so pkg ver up own_src=$2
	find "$1" -type f | while IFS= read -r f; do
		file -b "$f" | grep -q '^ELF 32-bit.*ARM aarch64' || continue
		readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'
	done | sort -u | while IFS= read -r so; do
		read -r _ pkg ver < <(awk -v s="$so" '$1 == s' "$W/sonames" | head -1) ||
			{ echo "no package ships $so" >&2; echo "MISSING:$so"; continue; }
		[ "$pkg" = "$3" ] && continue
		if [ "$(field "$pkg" source 2>/dev/null)" = "$own_src" ] && [ -n "$(version "$pkg")" ]; then
			echo "$pkg (= $ver)"
		else
			up=${ver%-*}
			echo "$pkg (>= $up)"
		fi
	done | sort -u | paste -sd, | sed 's/,/, /g'
}

# strip_tree <dir>: like dh_strip; .note.gnu.property (BTI) stays
strip_tree() {
	local f t
	while IFS= read -r -d '' f; do
		t=$(file -b "$f")
		case $t in
		"ELF 32-bit"*"ARM aarch64"*"shared object"* | "ELF 32-bit"*"ARM aarch64"*executable*)
			"$STRIP" --strip-unneeded --remove-section=.comment "$f" ;;
		"current ar archive"*) "$STRIP" --strip-debug "$f" ;;
		esac
	done < <(find "$1" -type f -print0)
}

for p in $PKGS; do
	ver=$(version "$p")
	src=$(field "$p" source)
	section=$(field "$p" section)
	desc=$(field "$p" desc)
	[ -n "$ver" ] && [ -n "$src" ] && [ -n "$section" ] && [ -n "$desc" ] ||
		{ echo "$p: version, source, section or desc missing in the MANIFEST" >&2; exit 1; }
	[ -d "$SNAP/$p" ] || { echo "$p: no tree in $SNAP" >&2; exit 1; }
	for f in copyright changelog; do
		[ -s "$SNAP/doc/$src.$f" ] || { echo "missing $SNAP/doc/$src.$f" >&2; exit 1; }
	done
	D=$W/pkg/$p
	mkdir -p "$D"
	cp -a "$SNAP/$p"/. "$D"/
	chmod -R u+rwX,go-w,go+rX "$D"
	strip_tree "$D"
	case $p in
	*-dev-ilp32)
		deps=""
		for r in $PKGS; do
			case $r in *-dev-ilp32) ;; *) [ "$(field "$r" source)" = "$src" ] && deps="$deps, $r (= $(version "$r"))" ;; esac
		done
		extra=$(block dev-depends | awk -v p="$p" '$1 == p { $1 = ""; sub(/^ +/, ""); print; exit }')
		[ -n "$extra" ] && deps="$deps, $extra"
		deps=${deps#, }
		;;
	*)
		deps=$(shlib_deps "$D" "$src" "$p")
		case $deps in *MISSING:*) echo "$p: unresolved sonames: $deps" >&2; exit 1 ;; esac
		;;
	esac
	mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$p"
	cp "$SNAP/doc/$src.copyright" "$D/usr/share/doc/$p/copyright"
	{
		cat <<EOF
$p ($ver) trixie; urgency=medium

  * Debian's $src ${ver%+ilp32a64.*} built for the AArch64 ILP32 ABI
    (aarch64-linux-gnu_ilp32), installed in /usr/libilp32; see
    https://github.com/ilp32-a64/debian-ilp32 for the patches and options.

 -- $MAINT  $(LC_ALL=C TZ=UTC date -R)

EOF
		awk '{ print } /^ -- / { exit }' "$SNAP/doc/$src.changelog"
	} | gzip -9n > "$D/usr/share/doc/$p/changelog.Debian.gz"
	{
		echo "Package: $p"
		echo "Source: $src-ilp32"
		echo "Version: $ver"
		echo "Architecture: arm64"
		echo "Maintainer: $MAINT"
		echo "Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)"
		[ -n "$deps" ] && echo "Depends: $deps"
		echo "Section: $section"
		echo "Priority: optional"
		echo "Homepage: https://github.com/ilp32-a64/debian-ilp32"
		echo "Description: $desc"
		echo " Debian's $src built for the AArch64 ILP32 ABI, installed next to the system's"
		echo " LP64 libraries: libraries in /usr/libilp32, headers in"
		echo " /usr/$T/include."
	} > "$D/DEBIAN/control"
	(cd "$D" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z |
		xargs -0r md5sum > DEBIAN/md5sums)
	dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT/${p}_${ver#*:}_arm64.deb" >/dev/null
	echo "built $OUT/${p}_${ver#*:}_arm64.deb"
done
