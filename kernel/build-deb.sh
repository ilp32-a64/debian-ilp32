#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the kernel packages (make bindeb-pkg): linux-ilp32 branch ilp32-6.12.y with the arm64 kernel
# configuration of Debian 13 (config-debian) plus the AArch64 ILP32 ABI, built like Debian's kernel:
# - in a Debian 13 chroot with Debian's cross toolchain (gcc-14, binutils, pahole): setup-chroot.sh,
#   then run this through chroot-run.sh
# - Debian's debug info and BTF settings (the -dbg package goes to OUT/dbg/; it is not published), or no
#   debug info with NODEBUG=1
# - an uncompressed Image as /boot/vmlinuz-* (KBUILD_IMAGE), the AArch32 compat vDSO (CROSS_COMPILE_COMPAT)
# - Debian's patch for kernel.perf_event_paranoid=3 (patches/, applied to KERNEL_TREE)
# No build user, host or path in the packages: KBUILD_BUILD_USER/HOST, -ffile-prefix-map.
#
# Usage: chroot-run.sh --fresh env [VAR=...] kernel/build-deb.sh     (release builds: a fresh chroot)
#        chroot-run.sh env [VAR=...] kernel/build-deb.sh             (development builds)
#   KERNEL_SRC       linux-ilp32 work tree to build from (default ~/work/wt/ilp32-6.12.y)
#   REV              commit of KERNEL_SRC (default HEAD)
#   KERNEL_TREE      work tree for the build: REV plus patches/, reset on every run
#                    (default ~/work/wt/debian-kernel; created with git worktree if missing)
#   KERNEL_BUILD     build directory (default ~/work/build/debian-ilp32-kernel)
#   OUT              output directory (default ~/work/debian-ilp32-kernel/out)
#   JOBS             parallel jobs (default 2)
#   KDEB_PKGVERSION  package version (default 6.12.114-1+ilp32a64.1)
#   KLOCALVERSION    release suffix (default -ilp32-arm64: linux-image-<version>-ilp32-arm64)
#   NODEBUG=1        no debug info, no BTF, no -dbg package
# Output: OUT/linux-image-*.deb, OUT/linux-headers-*.deb (published), OUT/linux-libc-dev_*.deb and
# OUT/dbg/ (not published), OUT/build.log, OUT/build-env.txt (the chroot: BUILD_CHROOT of chroot-run.sh
# and its package list)
set -euo pipefail
umask 022
D=$(dirname "$(realpath "$0")")
WT=${KERNEL_SRC:-$HOME/work/wt/ilp32-6.12.y}
SRC=${KERNEL_TREE:-$HOME/work/wt/debian-kernel}
O=${KERNEL_BUILD:-$HOME/work/build/debian-ilp32-kernel}
OUT=${OUT:-$HOME/work/debian-ilp32-kernel/out}
export KDEB_PKGVERSION=${KDEB_PKGVERSION:-6.12.114-1+ilp32a64.1}
LV=${KLOCALVERSION:--ilp32-arm64}
REV=$(git -C "$WT" rev-parse "${REV:-HEAD}")
. /etc/os-release
[ "$ID $VERSION_CODENAME" = "debian trixie" ] || { echo "not in Debian 13: run it through chroot-run.sh"; exit 1; }
export KBUILD_BUILD_USER=ilp32 KBUILD_BUILD_HOST=ilp32-a64
export DEBEMAIL=344781483+liviyifan@users.noreply.github.com DEBFULLNAME=liviyifan
# a Debian 13 package (the default is the build host's codename); UTC for the changelog date and the
# kernel build timestamp (uname -v), so that they do not show the time zone of the build host
export KDEB_CHANGELOG_DIST=trixie TZ=UTC
# uname -v: the commit time of REV, in UTC (reproducible). UTS_VERSION is only written when vmlinux is
# linked, so vmlinux is removed below to get it rewritten on every run.
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$(git -C "$WT" log -1 --format=%ct "$REV")" '+%a %b %e %H:%M:%S UTC %Y')"
M=(make -C "$SRC" O="$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-14
   CROSS_COMPILE_COMPAT=arm-linux-gnueabihf- KBUILD_IMAGE=arch/arm64/boot/Image
   LOCALVERSION="$LV" KCFLAGS="-ffile-prefix-map=$SRC/= -ffile-prefix-map=$O/="
   DPKG_FLAGS=-d HOSTPKG_CONFIG="$D/pkg-config-ssl")
# CROSS_COMPILE_COMPAT: the compiler of the AArch32 vDSO (COMPAT_VDSO, as in Debian).
# KBUILD_IMAGE: Debian installs an uncompressed Image, which also suits boot loaders without gzip
# support (U-Boot booti, Raspberry Pi firmware).
# DPKG_FLAGS=-d: no Build-Depends check (it would ask for arm64 packages the host tools do not need).
# HOSTPKG_CONFIG: the arm64 sign-file of linux-headers links against Debian 13's arm64 libcrypto
# (libssl-dev:arm64 in the chroot); see pkg-config-ssl.

# the work tree: REV plus patches/
[ -e "$SRC/.git" ] || git -C "$WT" worktree add -q --detach "$SRC" "$REV"
git -C "$SRC" checkout -q --detach "$REV"
git -C "$SRC" reset -q --hard "$REV"
for p in "$D"/patches/*.patch; do
	git -C "$SRC" apply "$p"
	echo "==> patch $(basename "$p")"
done
echo "==> $(git -C "$SRC" log -1 --format='%h %s'), package version $KDEB_PKGVERSION"
echo "==> $(aarch64-linux-gnu-gcc-14 --version | head -1); $(aarch64-linux-gnu-ld --version | head -1)"
mkdir -p "$O" "$OUT"
# the build environment, next to the packages
{ echo "# $KDEB_PKGVERSION built in: ${BUILD_CHROOT:-unknown}"; echo "# Debian $(cat /etc/debian_version)"
  COLUMNS=250 dpkg -l; } > "$OUT/build-env.txt"
echo "==> build chroot: ${BUILD_CHROOT:-unknown}"
cp "$D/config-debian" "$O/.config"
# ILP32 (COMPAT is on in Debian; AARCH32_EL0 keeps AArch32 as in Debian), no LOCALVERSION from the config
# (LOCALVERSION=$LV on the command line), binder built in (a module in Debian only with Debian's patches
# for it); debug info and BTF as in Debian (DWARF of the compiler default, BTF for vmlinux and the
# modules, needs pahole), or none with NODEBUG=1
if [ -n "${NODEBUG:-}" ]; then
	DBG=(-d DEBUG_INFO -e DEBUG_INFO_NONE -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT -d DEBUG_INFO_DWARF4
	     -d DEBUG_INFO_DWARF5 -d DEBUG_INFO_BTF -d DEBUG_INFO_BTF_MODULES)
	NEED_DBG=(DEBUG_INFO_NONE)
else
	DBG=()
	NEED_DBG=(DEBUG_INFO DEBUG_INFO_BTF DEBUG_INFO_BTF_MODULES)
	echo "==> pahole $(pahole --version 2>/dev/null || echo 'missing: install dwarves')"
fi
# PINCTRL_MCP23S08 (not in Debian): the MCP23017 I2C GPIO expander of the CN9130 CRB board (cp0 i2c
# 0x20, marvell/cn9130-crb-A/B.dtb), which the USB-A VBUS, eMMC VCCQ and SFP regulators depend on; it
# selects PINCTRL_MCP23S08_I2C and _SPI
"$SRC/scripts/config" --file "$O/.config" \
	-e COMPAT -e AARCH32_EL0 -e ARM64_ILP32 -e COMPAT_32BIT_TIME -e ANDROID_BINDER_IPC "${DBG[@]}" \
	-m PINCTRL_MCP23S08 -d LOCALVERSION_AUTO --set-str LOCALVERSION ""
"${M[@]}" -s olddefconfig
for o in COMPAT AARCH32_EL0 ARM64_ILP32 COMPAT_32BIT_TIME ARM64_PTR_AUTH ARM64_PTR_AUTH_KERNEL ARM64_BTI \
	 ARM64_SVE COMPAT_VDSO THUMB2_COMPAT_VDSO RELR ANDROID_BINDER_IPC SECURITY_PERF_EVENTS_RESTRICT \
	 "${NEED_DBG[@]}"; do
	grep -q "^CONFIG_$o=y" "$O/.config" || { echo "CONFIG_$o is not y"; exit 1; }
done
for o in PINCTRL_MCP23S08 PINCTRL_MCP23S08_I2C; do
	grep -q "^CONFIG_$o=m" "$O/.config" || { echo "CONFIG_$o is not m"; exit 1; }
done
echo "==> kernel release $("${M[@]}" -s kernelrelease), $(grep -c '=m$' "$O/.config") modules," \
     "build time $KBUILD_BUILD_TIMESTAMP"
rm -f "$O/vmlinux"
t=$(date +%s)
"${M[@]}" -j"${JOBS:-2}" bindeb-pkg > "$OUT/build.log" 2>&1 || { echo "==> BUILD FAILED"; tail -20 "$OUT/build.log"; exit 1; }
echo "==> BUILD OK in $(( $(date +%s) - t )) s, warnings: $(grep -c 'warning:' "$OUT/build.log")"
mv "$O"/../*_"$KDEB_PKGVERSION"_arm64.deb "$O"/../*_"$KDEB_PKGVERSION"_arm64.buildinfo \
   "$O"/../*_"$KDEB_PKGVERSION"_arm64.changes "$OUT/" 2>/dev/null || true
# the -dbg package (DWARF, about 1 GB, with build paths) is not published
mkdir -p "$OUT/dbg"
mv "$OUT"/linux-image-*-dbg_"$KDEB_PKGVERSION"_arm64.deb "$OUT/dbg/" 2>/dev/null || true
"$D/fix-headers-deb.sh" "$OUT"/linux-headers-*_"$KDEB_PKGVERSION"_arm64.deb
# /boot/config-* as Debian installs it: without the lines of the build's own module signing key and
# build salt, which Debian's rules.real deletes too (they make no sense for another build)
W=$(mktemp -d)
fakeroot sh -e -c '
	dpkg-deb -R "$1" "$2/x"
	c=$(echo "$2"/x/boot/config-*)
	sed -i "/CONFIG_\(MODULE_SIG_\(ALL\|KEY\)\|SYSTEM_TRUSTED_KEYS\|BUILD_SALT\)[ =]/d" "$c"
	r=${c#"$2"/x/}
	sed -i "\\|  $r\$|d" "$2/x/DEBIAN/md5sums"
	(cd "$2/x" && md5sum "$r") >> "$2/x/DEBIAN/md5sums"
	# Installed-Size as dpkg-gencontrol counts it: KiB of each file rounded up, 1 for anything else
	k=$(find "$2/x" -path "$2/x/DEBIAN" -prune -o ! -path "$2/x" -printf "%y %s\n" |
		awk "{ k += \$1 == \"f\" ? int((\$2 + 1023) / 1024) : 1 } END { print k }")
	sed -i "s/^Installed-Size: .*/Installed-Size: $k/" "$2/x/DEBIAN/control"
	dpkg-deb -Zxz --root-owner-group -b "$2/x" "$1" > /dev/null
' sh "$(echo "$OUT"/linux-image-*-ilp32-arm64_"$KDEB_PKGVERSION"_arm64.deb)" "$W"
rm -rf "$W"
echo "==> /boot/config: without MODULE_SIG_ALL, MODULE_SIG_KEY, SYSTEM_TRUSTED_KEYS, BUILD_SALT"
# package metadata: changelog distribution trixie, UTC times, the noreply maintainer; no build path in
# any file (no pipes that stop reading early: with pipefail, SIGPIPE would end the script without a
# message)
W=$(mktemp -d)
for deb in "$OUT"/linux-image-*_"$KDEB_PKGVERSION"_arm64.deb "$OUT"/linux-headers-*_"$KDEB_PKGVERSION"_arm64.deb; do
	rm -rf "$W/x"
	dpkg-deb -x "$deb" "$W/x"
	cl=$(zcat "$W"/x/usr/share/doc/*/changelog.Debian.gz)
	[[ "${cl%%$'\n'*}" == *") trixie;"* ]] || { echo "ERROR: $(basename "$deb"): changelog not trixie"; exit 1; }
	[[ "$cl" == *$'\n'" -- "*"+0000"* ]] || { echo "ERROR: $(basename "$deb"): changelog time not UTC"; exit 1; }
	[ "$(dpkg-deb -f "$deb" Maintainer)" = "$DEBFULLNAME <$DEBEMAIL>" ] ||
		{ echo "ERROR: $(basename "$deb"): maintainer"; exit 1; }
	! grep -rqF -e "$SRC" -e "$O" "$W/x" || { echo "ERROR: $(basename "$deb"): build path in a file"; exit 1; }
done
# /boot/vmlinuz-*: an uncompressed Image (arm64 Image magic "ARM\x64" at offset 56), Debian's compiler
# in the banner (/proc/version), and UTS_VERSION ("#1... SMP <time>", a string of its own that the banner
# takes at run time)
IMG=$(dpkg-deb -f "$OUT"/linux-image-*-ilp32-arm64_"$KDEB_PKGVERSION"_arm64.deb Package)
dpkg-deb -x "$OUT/${IMG}_${KDEB_PKGVERSION}_arm64.deb" "$W/img"
cfg=$(cat "$W"/img/boot/config-*)
[[ ! "$cfg" =~ CONFIG_(MODULE_SIG_ALL|MODULE_SIG_KEY|SYSTEM_TRUSTED_KEYS|BUILD_SALT)[\ =] ]] ||
	{ echo "ERROR: /boot/config has ${BASH_REMATCH[0]}"; exit 1; }
I=$(echo "$W"/img/boot/vmlinuz-*)
[ "$(od -An -c -j56 -N4 "$I" | tr -d ' ')" = 'ARMd' ] || { echo "ERROR: $I is not an uncompressed Image"; exit 1; }
s=$(strings "$I")
[[ "$s" != *Ubuntu* ]] || { echo "ERROR: Ubuntu in the kernel image"; exit 1; }
[[ "$s" == *"(Debian 14."* ]] || { echo "ERROR: not built with Debian's gcc"; exit 1; }
v=$(grep -E "^#[0-9]+.* SMP .* 20[0-9][0-9]$" <<< "$s" | sort -u || true)
[ "${v#* SMP }" = "$KBUILD_BUILD_TIMESTAMP" ] || { echo "ERROR: kernel build time is not $KBUILD_BUILD_TIMESTAMP: $v"; exit 1; }
rm -rf "$W"
echo "==> metadata: trixie, UTC, maintainer $DEBFULLNAME <$DEBEMAIL>; uncompressed Image, Debian's compiler"
if [ -z "${NODEBUG:-}" ]; then
	# BTF of vmlinux and of a module that is always built (ext4)
	W=$(mktemp -d)
	dpkg-deb -x "$OUT/${IMG}_${KDEB_PKGVERSION}_arm64.deb" "$W"
	xz -dc "$(find "$W" -name ext4.ko.xz)" > "$W/ext4.ko"
	for f in "$O/vmlinux" "$W/ext4.ko"; do
		[[ "$(aarch64-linux-gnu-readelf -S -W "$f")" == *" .BTF "* ]] || { echo "ERROR: no .BTF in $f"; exit 1; }
	done
	rm -rf "$W"
	echo "==> BTF: vmlinux and modules; -dbg package in $OUT/dbg/ (not published)"
fi
# GitHub Pages: no file of 100 MB or more
n=$(stat -c %s "$OUT/${IMG}_${KDEB_PKGVERSION}_arm64.deb")
[ "$n" -lt 100000000 ] || { echo "ERROR: ${IMG} .deb is $n bytes (limit 100000000)"; exit 1; }
ls -l "$OUT"/*.deb
