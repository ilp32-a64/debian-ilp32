#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs inside Debian 13 arm64 (see run-upgrade-test.sh): "apt install ilp32-runtime" must not
# bring in a kernel; "apt install linux-image-ilp32-arm64" installs the kernel; "apt upgrade"
# from v2 must follow the new kernel package name and upgrade the runtime.
R=/ilp32-test/repos
SRC=/etc/apt/sources.list.d/ilp32-a64.sources
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
show() { dpkg -l ilp32-runtime 'linux-image-*' '*-ilp32' 2>/dev/null | grep '^ii'; }

mkdir -p /boot/efi && mount /boot/efi
mkdir -p /root/apt-off
mv /etc/apt/sources.list /root/apt-off/ 2>/dev/null

step "U1 apt install ilp32-runtime (v1): runtime only, no kernel"
check dpkg -i /ilp32-test/keyring/ilp32-a64-archive-keyring_*_all.deb
use_repo v1
check apt install -y -q ilp32-runtime
show
check installed ilp32-runtime 2026.10.24
check installed libgomp1-ilp32 14.3.0-1+ilp32a64.1
check not_installed linux-image-ilp32-arm64
check not_installed linux-image-6.12.114-ilp32-arm64

step "U2 apt install linux-image-ilp32-arm64 (v1)"
check apt install -y -q linux-image-ilp32-arm64
show
check installed linux-image-ilp32-arm64 6.12.114+ilp32a64.1
check installed linux-image-6.12.114-ilp32-arm64 6.12.114-1+ilp32a64.1
check grep -q 'vmlinuz-6.12.114-ilp32-arm64' /boot/grub/grub.cfg
check /ilp32-test/bin/runtime-test

step "U3 apt-get upgrade (v2) keeps back packages that need new packages"
use_repo v2
apt-get upgrade -y -q 2>&1 | grep -iE 'kept back|upgraded,' | sed 's/^/INFO /'

step "U4 apt upgrade (v2) follows the new kernel"
check apt upgrade -y -q
show
check installed ilp32-runtime 2026.10.25
check installed linux-image-ilp32-arm64 6.12.999+ilp32a64.1
check installed linux-image-6.12.999-ilp32-arm64 6.12.999-1+ilp32a64.1
check installed linux-image-6.12.114-ilp32-arm64 6.12.114-1+ilp32a64.1
check installed libc6-ilp32 2.41-1+ilp32a64.2
check installed libstdc++6-ilp32 14.3.0-1+ilp32a64.2
check /ilp32-test/bin/runtime-test
check dpkg --audit
umount /boot/efi
