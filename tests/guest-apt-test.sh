#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs inside Debian 13 arm64 on the ILP32 kernel (see run-apt-test.sh): install the keyring
# package, install the runtime with apt from the signed test repository, and check that apt
# refuses unsigned, wrongly signed and tampered repositories.
R=/ilp32-test/repos
SRC=/etc/apt/sources.list.d/ilp32-a64.sources
PKGS="libc6-ilp32 libgcc-s1-ilp32 libstdc++6-ilp32 libatomic1-ilp32 libgomp1-ilp32"
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }
# must_fail <what> <grep pattern> <command...>: the command must fail and print the pattern.
must_fail() {
	local what=$1 pat=$2 out r
	shift 2
	out=$("$@" 2>&1); r=$?
	echo "$out" | grep -E '^(E|W|Err):|rror|mismatch' | head -5
	if [ $r != 0 ] && echo "$out" | grep -qE "$pat"; then
		echo "RESULT ok: refused: $what"
	else
		echo "RESULT FAIL: not refused ($r): $what"
	fi
}
use_repo() {
	sed -i "s|^URIs: .*|URIs: file:$R/$1|" $SRC
	rm -rf /var/lib/apt/lists/*
	apt-get clean
}
update_clean() {
	local out r
	out=$(apt-get update 2>&1); r=$?
	echo "$out" | grep -E '^(Get|Hit|Ign|Err|E|W):'
	if [ $r = 0 ] && ! echo "$out" | grep -qE '^(E|W|Err):'; then
		echo "RESULT ok: apt-get update without errors or warnings"
	else
		echo "RESULT FAIL($r): apt-get update"
	fi
}

step "K0 offline: only the ILP32-A64 source"
mkdir -p /root/apt-off
mv /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /root/apt-off/ 2>/dev/null
ls /etc/apt/sources.list.d/

step "K1 keyring package"
check dpkg -i /ilp32-test/keyring/ilp32-a64-archive-keyring_*_all.deb
cat $SRC
check test -s /usr/share/keyrings/ilp32-a64-archive.gpg

step "K2 signed repository: update and install"
use_repo good
update_clean
apt-cache policy libc6-ilp32 | head -4
check apt-get install -y -q $PKGS
dpkg -l '*-ilp32' | grep '^ii'
check /ilp32-test/bin/hello-ilp32
check /ilp32-test/bin/hello++-ilp32
check /ilp32-test/bin/runtime-test

step "K3 unsigned repository"
use_repo unsigned
must_fail "unsigned repository" "not signed|NO_PUBKEY|no longer signed|not valid" apt-get update

step "K4 repository signed with another key"
use_repo wrongkey
must_fail "wrong key" "NO_PUBKEY|not signed|signatures couldn't be verified|not valid" apt-get update

step "K5 Packages changed after signing"
use_repo badindex
must_fail "tampered index" "mismatch|unexpected size|Hash Sum" apt-get update

step "K6 .deb changed after signing"
use_repo baddeb
update_clean
must_fail "tampered .deb" "mismatch|unexpected size|Hash Sum" apt-get install -y -q --reinstall libgomp1-ilp32

step "K7 back to the signed repository"
use_repo good
update_clean
check apt-get install -y -q --reinstall libgomp1-ilp32
check /ilp32-test/bin/runtime-test
