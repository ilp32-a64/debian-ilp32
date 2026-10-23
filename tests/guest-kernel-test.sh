#!/bin/bash
# SPDX-License-Identifier: MIT
# Kernel package test inside the guest (see run-kernel-test.sh).
# Usage: guest-kernel-test.sh install <release> <expect ilp32 0|1>
#        guest-kernel-test.sh boot <release> <expect ilp32 0|1>
MODE=$1 REL=$2 ILP32=$3
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }

case $MODE in
install)
	step "B1 install the kernel package (running $(uname -r))"
	mount /boot/efi
	check dpkg -i /ilp32-test/kdebs/linux-image-*.deb
	ls -l /boot
	check test -f "/boot/vmlinuz-$REL"
	check test -f "/boot/initrd.img-$REL"
	check test -d "/lib/modules/$REL/kernel"
	check grep -q "vmlinuz-$REL" /boot/grub/grub.cfg
	grep -E "^\s*(menuentry|linux|initrd)" /boot/grub/grub.cfg | head -6
	lsinitramfs "/boot/initrd.img-$REL" | grep -E "virtio_(blk|pci)|/ext4" | head -5
	umount /boot/efi
	# The next boot (through GRUB) runs the boot phase.
	sed -i 's/guest-kernel-test.sh install/guest-kernel-test.sh boot/' /ilp32-test/test.sh
	grep -q 'RESULT FAIL' /dev/null
	echo KERNEL-INSTALL-OK
	;;
boot)
	step "B2 booted through GRUB"
	cat /proc/cmdline
	check test "$(uname -r)" = "$REL"
	cat /proc/version
	echo "modules loaded: $(cut -d' ' -f1 /proc/modules | sort | tr '\n' ' ')"
	grep -m1 -o 'paca\|bti' /proc/cpuinfo | sort -u | tr '\n' ' '; echo
	grep -E '^CONFIG_(ARM64_ILP32|COMPAT|AARCH32_EL0|COMPAT_32BIT_TIME|ARM64_PTR_AUTH|ARM64_BTI|ARM64_SVE)=' "/boot/config-$REL"
	check /usr/bin/true
	if grep -q "^CONFIG_DEBUG_INFO_BTF=y" "/boot/config-$REL"; then
		check test -s /sys/kernel/btf/vmlinux
		echo "BTF: vmlinux $(stat -c %s /sys/kernel/btf/vmlinux) bytes, $(ls /sys/kernel/btf | wc -l) objects"
	else
		echo "INFO: kernel without BTF"
	fi
	if [ "$ILP32" = 1 ]; then
		check grep -q '^CONFIG_ARM64_ILP32=y' "/boot/config-$REL"
		/ilp32-test/guest-install-test.sh /ilp32-test/debs /ilp32-test/bin
	else
		echo "kernel without ILP32: ILP32 programs must be refused"
		/ilp32-test/bin/hello-ilp32; r=$?
		if [ $r != 0 ]; then echo "RESULT ok: ILP32 refused ($r)"; else echo "RESULT FAIL: ILP32 ran"; fi
	fi
	;;
esac
