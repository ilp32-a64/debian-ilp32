#!/bin/bash
# SPDX-License-Identifier: MIT
# Fix up a linux-headers .deb made by bindeb-pkg (cross build), in place:
# - remove scripts/mod/devicetable-offsets.s: an intermediate file whose -fverbose-asm comments carry the
#   absolute source path of the build (-ffile-prefix-map does not apply to them)
# - remove tools/bpf/resolve_btfids/: a binary of the build host (x86-64, with build paths), which
#   install-extmod-build does not rebuild for the target. Module builds only run it with a vmlinux in the
#   headers directory, which the package does not have (they skip BTF for the module then).
# - make the kernel's compiler (aarch64-linux-gnu-gcc-14) the default CC for native module builds
# - Depends: gcc-14, make, libc6-dev; Installed-Size recomputed
# Then check that every ELF file left is an AArch64 one without a /home/ path.
#
# Usage: fix-headers-deb.sh <linux-headers-*.deb>     (rewritten as root:root via fakeroot)
set -euo pipefail
umask 022
DEB=$(realpath "${1:?usage: fix-headers-deb.sh <linux-headers-*.deb>}")
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fakeroot sh -e -c '
	n=0
	dpkg-deb -R "$1" "$2/x"
	for f in $(find "$2/x" -path "*/scripts/mod/devicetable-offsets.s" -o -path "*/tools/bpf/resolve_btfids" -prune); do
		rm -r "$f"
		n=$((n + 1))
	done
	find "$2/x" -path "*/tools/bpf" -type d -empty -delete
	# the compiler of the kernel (aarch64-linux-gnu-gcc-14 of gcc-14) by default for native module builds,
	# not gcc (another package, maybe another version), as Debian does; CROSS_COMPILE or CC= still win
	m=$(echo "$2"/x/usr/src/linux-headers-*/Makefile)
	if ! grep -q "aarch64-linux-gnu-gcc-14)\$" "$m"; then
		[ "$(grep -Ec "^CC[[:space:]]+= [\$][(]CROSS_COMPILE[)]gcc\$" "$m")" = 1 ] &&
		[ "$(grep -Ec "^HOSTCC[[:space:]]+= gcc\$" "$m")" = 1 ] ||
			{ echo "ERROR: compiler lines not found in $m"; exit 1; }
		sed -E -i -e "s/^(CC[[:space:]]+= )[\$][(]CROSS_COMPILE[)]gcc\$/\\1\$(if \$(CROSS_COMPILE),\$(CROSS_COMPILE)gcc,aarch64-linux-gnu-gcc-14)/" \
		       -e "s/^(HOSTCC[[:space:]]+= )gcc\$/\\1gcc-14/" "$m"
	fi
	r=${m#"$2"/x/}
	sed -i "\\|  $r\$|d" "$2/x/DEBIAN/md5sums"
	(cd "$2/x" && md5sum "$r") >> "$2/x/DEBIAN/md5sums"
	echo "==> $(basename "$1"): default CC aarch64-linux-gnu-gcc-14, HOSTCC gcc-14"
	sed -i -e "\\|/scripts/mod/devicetable-offsets\\.s\$|d" -e "\\|/tools/bpf/resolve_btfids/|d" "$2/x/DEBIAN/md5sums"
	# Installed-Size as dpkg-gencontrol counts it: KiB of each file rounded up, 1 for anything else
	k=$(find "$2/x" -path "$2/x/DEBIAN" -prune -o ! -path "$2/x" -printf "%y %s\n" |
		awk "{ k += \$1 == \"f\" ? int((\$2 + 1023) / 1024) : 1 } END { print k }")
	sed -i "s/^Installed-Size: .*/Installed-Size: $k/" "$2/x/DEBIAN/control"
	# what external module builds need (Debian pulls these in through linux-kbuild and
	# linux-compiler-gcc-14-arm); gcc-14 provides the aarch64-linux-gnu-gcc-14 of the build (CC)
	sed -i -e "/^Depends:/d" -e "/^Architecture:/a Depends: gcc-14, make, libc6-dev" "$2/x/DEBIAN/control"
	dpkg-deb -Zxz --root-owner-group -b "$2/x" "$1" > /dev/null
	echo "==> $(basename "$1"): removed $n (devicetable-offsets.s, tools/bpf/resolve_btfids/)"
' sh "$DEB" "$W"
rm -rf "$W/x"
dpkg-deb -x "$DEB" "$W/x"
# (no pipes that stop reading early: with pipefail, SIGPIPE would hide a match)
while IFS= read -r -d '' f; do
	t=$(file -b "$f")
	[[ "$t" == ELF* ]] || continue
	[[ "$t" == *"ARM aarch64"* ]] || { echo "ERROR: ${f#"$W"/x}: not AArch64: ${t%%,*}"; exit 1; }
	s=$(strings -a "$f")
	[[ "$s" != */home/* ]] || { echo "ERROR: ${f#"$W"/x}: build path"; exit 1; }
done < <(find "$W/x" -type f -print0)
echo "==> $(basename "$DEB"): all ELF files AArch64, no /home/ paths"
