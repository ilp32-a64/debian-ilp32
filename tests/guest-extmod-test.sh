#!/bin/bash
# SPDX-License-Identifier: MIT
# External module test inside the guest (see run-extmod-test.sh).
# Usage: guest-extmod-test.sh install <release> <mirror>
#        guest-extmod-test.sh boot <release>
MODE=$1 REL=$2
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }

case $MODE in
install)
	step "E1 install kernel and headers (gcc and make come as dependencies)"
	ip link set lo up
	dev=$(ls /sys/class/net | grep -v lo | head -1)
	ip link set "$dev" up && ip addr add 10.0.2.15/24 dev "$dev" && ip route add default via 10.0.2.2
	echo "nameserver 10.0.2.3" > /etc/resolv.conf
	echo "deb $3 trixie main" > /etc/apt/sources.list
	mount /boot/efi
	check apt-get update -q
	# apt installs the local packages and pulls in what linux-headers depends on (gcc, make, ...)
	check apt-get install -y -q --no-install-recommends /ilp32-test/kdebs/*.deb
	check command -v gcc make
	check test -e "/lib/modules/$REL/build/Makefile"
	umount /boot/efi
	sed -i 's/guest-extmod-test.sh install/guest-extmod-test.sh boot/' /ilp32-test/test.sh
	echo EXTMOD-INSTALL-OK
	;;
boot)
	step "E2 build and load a module on $(uname -r)"
	check test "$(uname -r)" = "$REL"
	M=/root/hello-mod
	mkdir -p $M
	cat > $M/hello.c <<'EOF'
#include <linux/module.h>
#include <linux/init.h>

static int __init hello_init(void)
{
	pr_info("hello-ilp32-test: loaded\n");
	return 0;
}

static void __exit hello_exit(void)
{
	pr_info("hello-ilp32-test: unloaded\n");
}

module_init(hello_init);
module_exit(hello_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("external module build test");
EOF
	echo 'obj-m += hello.o' > $M/Makefile
	make -C "/lib/modules/$REL/build" M=$M modules > $M/build.log 2>&1
	r=$?
	sed 's/^/INFO build: /' $M/build.log | tail -8
	[ $r = 0 ] && echo "RESULT ok: make modules" || echo "RESULT FAIL($r): make modules"
	grep -q 'Skipping BTF generation' $M/build.log && echo "INFO: module built without BTF (as expected)"
	modinfo $M/hello.ko | grep -E '^(vermagic|name):' | sed 's/^/INFO /'
	check insmod $M/hello.ko
	dmesg | grep -q 'hello-ilp32-test: loaded' && echo "RESULT ok: module loaded" || echo "RESULT FAIL: module not loaded"
	grep -o 'hello.*' /proc/modules | head -1 | sed 's/^/INFO /'
	check rmmod hello
	dmesg | grep -E 'hello-ilp32-test|taint' | tail -3 | sed 's/^/INFO dmesg: /'
	;;
esac
