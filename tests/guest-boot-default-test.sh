#!/bin/bash
# SPDX-License-Identifier: MIT
# Default boot kernel test inside the guest (see run-boot-default-test.sh). Each boot runs one phase.
. /ilp32-test/versions
export DEBIAN_FRONTEND=noninteractive
Q=/ilp32-test/stock
OFF=/etc/default/ilp32-kernel
FW=/boot/firmware
MPKG=linux-image-ilp32-arm64
IPKG=linux-image-$ILP32
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }
fails() { "$@" > /dev/null 2>&1; local r=$?; if [ $r != 0 ]; then echo "RESULT ok: refused($r): $*"; else echo "RESULT FAIL: ran: $*"; fi; }
next() { echo "$1" > /ilp32-test/phase; }

network() {
	ip link set lo up
	local dev
	dev=$(ls /sys/class/net | grep -v lo | head -1)
	ip link set "$dev" up && ip addr add 10.0.2.15/24 dev "$dev" && ip route add default via 10.0.2.2
	echo "nameserver 10.0.2.3" > /etc/resolv.conf
}

# GRUB: the first menu entry's kernel, which GRUB_DEFAULT=0 boots
grub_first() { grep -m1 -E '^[[:space:]]*linux[[:space:]]' /boot/grub/grub.cfg | awk '{print $2}' | sed 's,.*/vmlinuz-,,'; }
grub_is() { [ "$(grub_first)" = "$1" ]; }
# extlinux: the default label's kernel
ext() { echo /boot/extlinux/extlinux.conf; }
ext_default() { awk '$1 == "default" { print $2; exit }' "$(ext)"; }
ext_first() { awk -v l="$(ext_default)" '$1 == "label" && $2 == l { f = 1 } f && $1 == "linux" { print $2; exit }' "$(ext)" | sed 's,.*/vmlinuz-,,'; }
ext_is() { [ "$(ext_first)" = "$1" ]; }
# raspi-firmware
pi_kernel() { sed -n 's/^kernel=vmlinuz-//p' $FW/config.txt; }
pi_initrd() { sed -n 's/^initramfs initrd.img-//p' $FW/config.txt; }
pi_is() { [ "$(pi_kernel)" = "$1" ] && [ "$(pi_initrd)" = "$1" ] && [ -f "$FW/vmlinuz-$1" ] && [ -f "$FW/initrd.img-$1" ]; }
pi_files_match() { cmp "/boot/vmlinuz-$1" "$FW/vmlinuz-$1" && cmp "/boot/initrd.img-$1" "$FW/initrd.img-$1"; }
no_tmp() { ! ls -A $FW | grep -q ilp32-kernel; }

configured() { [ "$(dpkg-query -W -f '${db:Status-Abbrev}' "$1" 2>/dev/null | cut -c1-2)" = ii ]; }
set_off() { sed -i "s/^ILP32_KERNEL_DEFAULT=.*/ILP32_KERNEL_DEFAULT=$1/" $OFF; }
nothing_left() {
	local left
	left=$(find /etc /usr/lib/ilp32-kernel /usr/share/u-boot-menu /usr/sbin/ilp32-kernel-update-boot -name '*ilp32-kernel*' 2>/dev/null)
	[ -z "$left" ] || { echo "left behind: $left"; return 1; }
	! dpkg-query -W -f '${db:Status-Abbrev}' $MPKG 2>/dev/null | grep -q '^[a-z]i\|^.c'
}
stubs_inert() { [ -e /etc/default/grub.d/ilp32-kernel.cfg ] && [ ! -e /usr/lib/ilp32-kernel/select ]; }

case $(cat /ilp32-test/phase) in
install)
	mkdir -p /boot/efi && mount /boot/efi
	network
	cat > /etc/apt/sources.list <<-EOF
	deb https://deb.debian.org/debian trixie main non-free-firmware
	deb https://security.debian.org/debian-security trixie-security main
	EOF
	check apt-get update -q
	step "G1 without the package, the higher Debian kernel is the default"
	check dpkg -i "$IMG"
	check apt-get install -y -q --no-install-recommends "linux-image-$LOW" "linux-image-$HIGH"
	check update-grub
	cp /boot/grub/grub.cfg $Q.grub
	echo "INFO first entry without the package: $(grub_first)"
	check grub_is "$HIGH"

	step "G2 with the package, the ILP32 kernel stays the default when a higher Debian kernel comes"
	check apt-get purge -y -q "linux-image-$HIGH"
	check apt-get install -y -q "$META"
	check grub_is "$ILP32"
	check apt-get install -y -q --no-install-recommends "linux-image-$HIGH"
	echo "INFO first entry with the package: $(grub_first)"
	check grub_is "$ILP32"
	check grep -q "vmlinuz-$HIGH" /boot/grub/grub.cfg
	check dpkg --audit
	umount /boot/efi
	next boot-on
	;;
boot-on)
	step "G3 booted through GRUB: the ILP32 kernel"
	echo "INFO running $(uname -r)"
	check test "$(uname -r)" = "$ILP32"
	check /ilp32-test/hello-ilp32
	next off
	;;
off)
	step "G4 off switch: grub.cfg as without the package"
	set_off no
	check /usr/sbin/ilp32-kernel-update-boot
	check grub_is "$HIGH"
	check cmp /boot/grub/grub.cfg $Q.grub
	next boot-off
	;;
boot-off)
	step "G5 booted through GRUB: Debian's kernel"
	echo "INFO running $(uname -r)"
	check test "$(uname -r)" = "$HIGH"
	fails /ilp32-test/hello-ilp32
	next rest
	;;
rest)
	network
	step "G6 on again"
	set_off yes
	check /usr/sbin/ilp32-kernel-update-boot
	check grub_is "$ILP32"

	step "G7 guards: no initrd, a user's GRUB_TOP_LEVEL and GRUB_DEFAULT, other kernels"
	mv "/boot/initrd.img-$ILP32" /ilp32-test/initrd.saved
	check update-grub
	check grub_is "$HIGH"
	mv /ilp32-test/initrd.saved "/boot/initrd.img-$ILP32"
	cp /etc/default/grub /ilp32-test/grub.saved
	echo "GRUB_TOP_LEVEL=/boot/vmlinuz-$LOW" >> /etc/default/grub
	check update-grub
	check grub_is "$LOW"
	cp /ilp32-test/grub.saved /etc/default/grub
	echo "GRUB_DEFAULT=2" >> /etc/default/grub
	check update-grub
	check grep -q 'set default="2"' /boot/grub/grub.cfg
	cp /ilp32-test/grub.saved /etc/default/grub
	touch /boot/vmlinuz-6.12.50-ilp32-arm64 /boot/initrd.img-6.12.50-ilp32-arm64 /boot/vmlinuz-6.12.999-ilp32-arm64
	sel=$(/usr/lib/ilp32-kernel/select)
	echo "INFO select with an older kernel and a newer one without an initrd: $sel"
	check test "$sel" = "$ILP32"
	touch /boot/initrd.img-6.12.999-ilp32-arm64
	check test "$(/usr/lib/ilp32-kernel/select)" = 6.12.999-ilp32-arm64
	rm -f /boot/vmlinuz-6.12.50-ilp32-arm64 /boot/initrd.img-6.12.50-ilp32-arm64 /boot/vmlinuz-6.12.999-ilp32-arm64 /boot/initrd.img-6.12.999-ilp32-arm64
	check test "$(/usr/lib/ilp32-kernel/select --other)" = "$HIGH"

	step "R1 remove the metapackage: inert conffiles; purge: nothing left"
	check apt-get remove -y -q $MPKG
	check stubs_inert
	check grub_is "$HIGH"
	check cmp /boot/grub/grub.cfg $Q.grub
	check update-grub
	check cmp /boot/grub/grub.cfg $Q.grub
	check apt-get purge -y -q $MPKG
	check nothing_left
	check cmp /boot/grub/grub.cfg $Q.grub

	step "R2 remove the kernel first: apt removes both"
	check apt-get install -y -q "$META"
	check grub_is "$ILP32"
	check apt-get purge -y -q "$IPKG"
	check nothing_left
	check grub_is "$HIGH"
	fails grep -q "vmlinuz-$ILP32" /boot/grub/grub.cfg

	step "R3 the last ILP32 kernel goes while the metapackage stays"
	check dpkg -i "$IMG"
	check apt-get install -y -q "$META"
	check dpkg --force-depends -r "$IPKG"
	check grub_is "$HIGH"
	check dpkg -i "$IMG"
	check grub_is "$ILP32"
	check apt-get purge -y -q $MPKG
	check nothing_left

	step "E1 extlinux: without the package"
	check apt-get install -y -q --no-install-recommends u-boot-menu
	check u-boot-update
	cp "$(ext)" $Q.ext
	echo "INFO extlinux default without the package: $(ext_default) = $(ext_first)"
	check ext_is "$HIGH"

	step "E2 extlinux: with the package, also after a Debian kernel hook"
	check apt-get install -y -q "$META"
	echo "INFO extlinux default with the package: $(ext_default) = $(ext_first)"
	check ext_is "$ILP32"
	check apt-get install -y -q --no-install-recommends --reinstall "linux-image-$HIGH"
	check ext_is "$ILP32"
	check apt-get purge -y -q "linux-image-$LOW"
	check ext_is "$ILP32"
	check apt-get install -y -q --no-install-recommends "linux-image-$LOW"
	check ext_is "$ILP32"

	step "E3 extlinux: off switch"
	set_off no
	check /usr/sbin/ilp32-kernel-update-boot
	check cmp "$(ext)" $Q.ext
	set_off yes
	check /usr/sbin/ilp32-kernel-update-boot
	check ext_is "$ILP32"

	step "E4 extlinux: a user's U_BOOT_DEFAULT, one entry only, no default entries"
	cp /etc/default/u-boot /ilp32-test/u-boot.saved
	echo 'U_BOOT_DEFAULT="l2"' >> /etc/default/u-boot
	check u-boot-update
	check test "$(ext_default)" = l2
	cp /ilp32-test/u-boot.saved /etc/default/u-boot
	echo 'U_BOOT_ENTRIES="1"' >> /etc/default/u-boot
	check u-boot-update
	check test "$(ext_default)" = l0
	check ext_is "$HIGH"
	cp /ilp32-test/u-boot.saved /etc/default/u-boot
	echo 'U_BOOT_ALTERNATIVES="recovery"' >> /etc/default/u-boot
	check u-boot-update
	check test "$(ext_default)" = l0
	cp /ilp32-test/u-boot.saved /etc/default/u-boot
	check u-boot-update

	step "E5 extlinux: remove the metapackage (u-boot-menu's trigger regenerates)"
	check apt-get remove -y -q $MPKG
	check cmp "$(ext)" $Q.ext
	check apt-get purge -y -q $MPKG u-boot-menu
	check nothing_left

	step "P1 raspi-firmware: without the package"
	mkdir -p $FW
	check mount -t tmpfs -o size=900M tmpfs $FW
	check apt-get install -y -q --no-install-recommends raspi-firmware
	DEB_MAINT_PARAMS=configure /etc/kernel/postinst.d/z50-raspi-firmware
	cp $FW/config.txt $Q.config; cp $FW/cmdline.txt $Q.cmdline
	echo "INFO config.txt without the package: $(pi_kernel)"
	check pi_is "$HIGH"

	step "P2 raspi-firmware: with the package, also after a Debian kernel hook"
	check apt-get install -y -q "$META"
	echo "INFO config.txt with the package: $(pi_kernel) / $(pi_initrd)"
	check pi_is "$ILP32"
	check pi_files_match "$ILP32"
	check pi_files_match "$HIGH"
	check apt-get install -y -q --no-install-recommends --reinstall "linux-image-$HIGH"
	check pi_is "$ILP32"
	check cmp "/usr/lib/linux-image-$ILP32/broadcom/bcm2837-rpi-3-b-plus.dtb" $FW/bcm2837-rpi-3-b-plus.dtb

	step "P3 raspi-firmware: off switch"
	set_off no
	check /usr/sbin/ilp32-kernel-update-boot
	check cmp $FW/config.txt $Q.config
	check cmp $FW/cmdline.txt $Q.cmdline
	set_off yes
	check /usr/sbin/ilp32-kernel-update-boot
	check pi_is "$ILP32"

	step "P4 raspi-firmware: its own upgrade, and update-initramfs alone"
	check apt-get install -y -q --no-install-recommends --reinstall raspi-firmware
	check dpkg --configure --pending
	echo "INFO after raspi-firmware reinstall: $(pi_kernel)"
	check pi_is "$ILP32"
	check update-initramfs -u -k "$ILP32"
	check pi_is "$ILP32"
	check pi_files_match "$ILP32"
	check update-initramfs -u -k "$HIGH"
	echo "INFO after update-initramfs of Debian's kernel: $(pi_kernel)"
	check pi_is "$ILP32"

	step "P5 raspi-firmware: a full firmware partition keeps z50's result"
	rm -f "$FW/vmlinuz-$ILP32" "$FW/initrd.img-$ILP32"
	used=$(df -Pk $FW | awk 'END { print $3 }')
	check mount -o "remount,size=$((used + 2048))k" $FW
	check /usr/sbin/ilp32-kernel-update-boot
	echo "INFO full partition: $(pi_kernel)"
	check pi_is "$HIGH"
	check no_tmp
	check mount -o remount,size=900M $FW
	check /usr/sbin/ilp32-kernel-update-boot
	check pi_is "$ILP32"

	step "P6 firmware not mounted during a Debian kernel install; the package arrives while stuck"
	check apt-get purge -y -q $MPKG "linux-image-$HIGH"
	mkdir -p /ilp32-test/fw
	# z50 and raspi-apply skip their mount check in a VM; hide the detection, as on a real Pi.
	[ ! -e /usr/bin/systemd-detect-virt ] || mv /usr/bin/systemd-detect-virt /ilp32-test/systemd-detect-virt.saved
	check mount --move $FW /ilp32-test/fw
	apt-get install -y -q --no-install-recommends "linux-image-$HIGH"
	echo "INFO kernel install with the partition unmounted: exit $?, state $(dpkg-query -W -f '${db:Status-Abbrev}' "linux-image-$HIGH")"
	check test ! -e $FW/config.txt
	fails configured "linux-image-$HIGH"
	check dpkg -i "$META"
	check configured $MPKG
	check mount --move /ilp32-test/fw $FW
	check dpkg --configure -a
	check configured "linux-image-$HIGH"
	echo "INFO after mount and dpkg --configure -a: $(pi_kernel)"
	check pi_is "$ILP32"

	step "P7 stuck the same way, but the package arrives after dpkg --configure -a"
	check apt-get purge -y -q $MPKG "linux-image-$HIGH"
	check mount --move $FW /ilp32-test/fw
	apt-get install -y -q --no-install-recommends "linux-image-$HIGH"
	echo "INFO kernel install with the partition unmounted: exit $?"
	check mount --move /ilp32-test/fw $FW
	check dpkg --configure -a
	echo "INFO without the package: $(pi_kernel)"
	check test "$(pi_kernel)" = "$HIGH"
	check dpkg -i "$META"
	check pi_is "$ILP32"
	check no_tmp
	[ ! -e /ilp32-test/systemd-detect-virt.saved ] || mv /ilp32-test/systemd-detect-virt.saved /usr/bin/systemd-detect-virt

	step "P8 raspi-firmware: remove with a lower Debian kernel that was never copied"
	check apt-get purge -y -q "linux-image-$HIGH"
	rm -f "$FW/vmlinuz-$LOW" "$FW/initrd.img-$LOW"
	check apt-get purge -y -q "$IPKG"
	check nothing_left
	echo "INFO after removal: $(pi_kernel)"
	check pi_is "$LOW"
	check pi_files_match "$LOW"
	check no_tmp

	step "end"
	check dpkg --audit
	echo BOOT-DEFAULT-DONE
	next done
	;;
esac
