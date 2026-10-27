#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs inside Debian 13 arm64 (see run-upgrade-test.sh): install from the previous release (v1),
# upgrade to the new release (v2) as the README says, then follow a new kernel package name (v3).
R=/ilp32-test/repos
SRC=/etc/apt/sources.list.d/ilp32-a64.sources
T=aarch64-linux-gnu_ilp32
. /ilp32-test/versions
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }
# installed <package> <version>: the package is installed at that version
installed() {
	local v
	v=$(dpkg-query -W -f '${db:Status-Abbrev}${Version}' "$1" 2>/dev/null)
	[ "$v" = "ii $2" ]
}
not_installed() { ! dpkg-query -W -f '${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'; }
use_repo() {
	sed -i "s|^URIs: .*|URIs: file:$R/$1|" $SRC
	apt-get update -q > /dev/null 2>&1 && echo "RESULT ok: apt update ($1)" || echo "RESULT FAIL: apt update ($1)"
}
show() { dpkg -l ilp32-runtime 'linux-image-*' '*-ilp32' 2>/dev/null | grep '^ii' | awk '{print "INFO", $2, $3}'; }
# build_run: build and run ILP32 programs with the installed compiler
build_run() {
	cd /root
	check $T-gcc -O2 -fopenmp -o runtime-test /ilp32-test/runtime-test.c -lm -latomic
	check ./runtime-test
	check $T-g++ -O2 -o hello++ /ilp32-test/hello++.cc
	check ./hello++
	cd /
}

mkdir -p /boot/efi && mount /boot/efi
ip link set lo up
dev=$(ls /sys/class/net | grep -v lo | head -1)
ip link set "$dev" up && ip addr add 10.0.2.15/24 dev "$dev" && ip route add default via 10.0.2.2
echo "nameserver 10.0.2.3" > /etc/resolv.conf
echo "deb $mirror trixie main" > /etc/apt/sources.list

step "U1 apt install ilp32-runtime (v1): runtime only, no kernel"
check dpkg -i /ilp32-test/keyring/ilp32-a64-archive-keyring_*_all.deb
use_repo v1
check apt install -y -q ilp32-runtime
check installed ilp32-runtime "$v1_ilp32_runtime"
check installed libc6-ilp32 "$v1_libc6_ilp32"
check not_installed linux-image-ilp32-arm64

step "U2 kernel and compiler (v1)"
check apt install -y -q linux-image-ilp32-arm64 gcc-aarch64-linux-gnu-ilp32 g++-aarch64-linux-gnu-ilp32
show
check installed linux-image-ilp32-arm64 "$v1_linux_image_ilp32_arm64"
check installed "$v1_kpkg" "$v1_kver"
check installed gcc-14-aarch64-linux-gnu-ilp32 "$v1_gcc_14_aarch64_linux_gnu_ilp32"
build_run

step "U3 apt upgrade (v2)"
use_repo v2
check apt upgrade -y -q
show
check installed ilp32-runtime "$v2_ilp32_runtime"
check installed linux-image-ilp32-arm64 "$v2_linux_image_ilp32_arm64"
check installed "$v2_kpkg" "$v2_kver"
check grep -q "vmlinuz-${v2_kpkg#linux-image-}" /boot/grub/grub.cfg
if dpkg --compare-versions "$v2_gcc_14_aarch64_linux_gnu_ilp32" lt "$v1_gcc_14_aarch64_linux_gnu_ilp32"; then
	echo "INFO the new compiler has a lower version: apt upgrade keeps the old one, and glibc,"
	echo "INFO which the old compiler's libc6-dev-ilp32 holds at its exact version"
	check installed gcc-14-aarch64-linux-gnu-ilp32 "$v1_gcc_14_aarch64_linux_gnu_ilp32"
	check installed libc6-ilp32 "$v1_libc6_ilp32"

	step "U4 the one-time downgrade from the README"
	printf 'Package: *\nPin: release o=ILP32-A64\nPin-Priority: 1001\n' > /etc/apt/preferences.d/ilp32-a64-once
	check apt upgrade -y -q --allow-downgrades
	rm /etc/apt/preferences.d/ilp32-a64-once
	show
fi
check installed gcc-14-aarch64-linux-gnu-ilp32 "$v2_gcc_14_aarch64_linux_gnu_ilp32"
check installed libc6-ilp32 "$v2_libc6_ilp32"
check installed libstdc++6-ilp32 "$v2_libstdc__6_ilp32"
check apt-get check
build_run
check dpkg --audit

step "U5 apt upgrade (v3) follows the new kernel package name"
use_repo v3
check apt upgrade -y -q
show
check installed linux-image-6.12.999-ilp32-arm64 6.12.999-1+ilp32a64.1
check installed "$v2_kpkg" "$v2_kver"
check dpkg --audit
umount /boot/efi
