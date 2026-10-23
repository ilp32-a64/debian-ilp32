#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs inside Debian 13 arm64 on the ILP32 kernel: install the runtime packages with dpkg,
# run the ILP32 test programs, check that Debian's ldconfig keeps them working, then remove
# and purge the packages and check that nothing is left behind.
# Usage: guest-install-test.sh <dir with *.deb> <dir with test programs>
DEBS=${1:?debs dir}
BIN=${2:?test program dir}
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }
run_all() {
	check "$BIN/hello-ilp32"
	check "$BIN/hello++-ilp32"
	check "$BIN/runtime-test"
}

step "R0 system"
uname -r
cat /etc/debian_version
grep -m1 -o 'paca\|bti' /proc/cpuinfo | sort -u | tr '\n' ' '; echo

step "R1 install"
check dpkg -i "$DEBS"/*.deb
dpkg -l '*-ilp32' | grep ilp32
ls -ld /libilp32 /usr/libilp32 /lib/ld-linux-aarch64_ilp32.so.1
dpkg -S /usr/lib/ld-linux-aarch64_ilp32.so.1 /libilp32

step "R2 run"
run_all

step "R3 after Debian's ldconfig"
check ldconfig
run_all
check /usr/bin/ls /

step "R4 dpkg --verify and audit"
check dpkg --verify libc6-ilp32 libgcc-s1-ilp32 libstdc++6-ilp32 libatomic1-ilp32 libgomp1-ilp32
check dpkg --audit

step "R5 purge"
check dpkg --purge libgomp1-ilp32 libatomic1-ilp32 libstdc++6-ilp32 libgcc-s1-ilp32 libc6-ilp32
ls -ld /libilp32 /usr/libilp32 /usr/lib/ld-linux-aarch64_ilp32.so.1 2>&1
check /usr/bin/ls /
"$BIN/hello-ilp32"; echo "hello-ilp32 without the runtime: exit $? (expected non-zero)"

step "R6 reinstall"
check dpkg -i "$DEBS"/*.deb
run_all
