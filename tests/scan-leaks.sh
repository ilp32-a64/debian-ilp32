#!/bin/bash
# SPDX-License-Identifier: MIT
# Fail if any .deb contains internal information. Every file is scanned with strings -a, after
# unpacking gzip, xz and zstd content (kernel modules, vmlinuz) next to it.
#
# Two sets of patterns:
#   build leaks  build paths (/home/, /root/), host names (ubuntu-VirtualBox and this host's
#                name), private IP ranges 192.168/16, 172.16/12 and 100.64/10
#   all          build leaks, plus 10/8 and the private list (board names, company names, ...)
#                kept outside the repository, so that the patterns themselves stay private
#                (default ~/.config/debian-ilp32/leak-patterns, or LEAK_PATTERNS)
#
# Upstream content gets the build-leak patterns only; our own metadata and scripts get all
# patterns. Upstream content is everything but our metadata in the kernel packages (linux-image-*,
# linux-headers-*: kernel, modules, device trees, config, headers, DEBIAN/md5sums) and in the
# toolchain packages (binutils, gcc, g++, libc6-dev and linux-libc-dev for ILP32: compilers,
# headers, static libraries). It carries upstream authors' email addresses, vendor and SoC names
# of upstream drivers, and specification section numbers that look like 10.x.x.x addresses, all
# published upstream. DEBIAN/control, changelog, copyright, maintainer scripts and /usr/share/doc
# are ours. Every other package (runtime, keyring, metapackages) is ours entirely.
# ALLOW_UPSTREAM lists exact exceptions.
#
# Each package ends with "SCANNED <file>: <n> files, <n> hits"; the scan fails unless every
# package was scanned.
# Usage: scan-leaks.sh <dir with *.deb>
set -euo pipefail
DEBS=$(realpath "${1:?usage: scan-leaks.sh <debs dir>}")
PRIVATE=${LEAK_PATTERNS:-$HOME/.config/debian-ilp32/leak-patterns}
ALLOW_UPSTREAM=(
	# linux-headers: scripts/rust_is_available_test.py, sample compiler output in upstream test data
	"/home/jd/Documents/dev/kernel-module-flake/linux-6.1/outputs/dev/lib/modules/6.1.0-development/source/scripts/rust_is_available_bindgen_libclang.h"
)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

{
	echo '/home/'
	echo '/root/'
	echo 'ubuntu-VirtualBox'
	h=$(hostname 2>/dev/null || true)
	[ -n "$h" ] && printf '%s\n' "$h" | sed 's/[][\.*^$+?(){}|/]/\\&/g'
	echo '(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
	echo '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
	echo '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
} | sort -u > "$W/build"
cp "$W/build" "$W/all"
echo '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)' >> "$W/all"
if [ -r "$PRIVATE" ]; then
	grep -v '^[[:space:]]*\(#\|$\)' "$PRIVATE" >> "$W/all" || true
else
	echo "warning: no private pattern list ($PRIVATE)" >&2
fi
printf '%s\n' "${ALLOW_UPSTREAM[@]}" > "$W/allow-upstream"
: > "$W/allow-none"

# scan <file list> <patterns> <allow list>: print the hits
scan() {
	[ -s "$1" ] || return 0
	tr '\n' '\0' < "$1" | xargs -0 strings -a -n 6 -f > "$W/strings" || true
	grep -E -i -f "$2" "$W/strings" | grep -v -F -f "$3" || true
}

ndebs=0 nscanned=0 bad=0
for deb in "$DEBS"/*.deb; do
	ndebs=$((ndebs + 1))
	name=$(dpkg-deb -f "$deb" Package)
	X=$W/x
	rm -rf "$X"
	dpkg-deb -R "$deb" "$X"
	cd "$X"
	# Unpack compressed files next to themselves, so their content is scanned too.
	find . -type f -print0 | xargs -0 file -N --mime-type -F '|' > "$W/types" 2>/dev/null || true
	find . -type f | sort > "$W/files0"
	while IFS='|' read -r f type; do
		case ${type# } in
		application/gzip) zcat -f -- "$f" > "$f.unpacked" 2>/dev/null || true ;;
		application/x-xz) xz -dc -- "$f" > "$f.unpacked" 2>/dev/null || true ;;
		application/zstd) zstd -dcq -- "$f" > "$f.unpacked" 2>/dev/null || true ;;
		esac
	done < "$W/types"
	find . -type f | sort > "$W/files"
	case $name in
	linux-image-*-ilp32-arm64 | linux-headers-*-ilp32-arm64 | linux-libc-dev-ilp32 | \
		libc6-dev-ilp32 | binutils-*-ilp32 | gcc-*-ilp32 | g++-*-ilp32)
		grep -E '^\./(DEBIAN/(control|changelog|copyright|conffiles|triggers|templates|config|preinst|postinst|prerm|postrm)|usr/share/doc/)' \
			"$W/files" > "$W/own" || true
		grep -v -x -F -f "$W/own" "$W/files" > "$W/upstream" || true
		;;
	*)
		cp "$W/files" "$W/own"
		: > "$W/upstream"
		;;
	esac
	{
		scan "$W/own" "$W/all" "$W/allow-none"
		scan "$W/upstream" "$W/build" "$W/allow-upstream"
	} > "$W/hits"
	cd "$W"
	nhits=$(wc -l < "$W/hits")
	if [ "$nhits" -gt 0 ]; then
		echo "LEAK in $(basename "$deb"):"
		sed -n '1,20s/^/  /p' "$W/hits"
		bad=1
	fi
	nscanned=$((nscanned + 1))
	echo "SCANNED $(basename "$deb"): $(wc -l < "$W/files0") files ($(($(wc -l < "$W/files") - $(wc -l < "$W/files0"))) unpacked), own $(wc -l < "$W/own"), upstream $(wc -l < "$W/upstream"), $nhits hits"
done
if [ "$nscanned" != "$ndebs" ] || [ "$ndebs" = 0 ]; then
	echo "leak scan: only $nscanned of $ndebs packages scanned" >&2
	exit 1
fi
[ $bad = 0 ] && echo "leak scan: clean ($ndebs packages)"
exit $bad
