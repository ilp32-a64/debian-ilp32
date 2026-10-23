#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs once inside the new EFI base image (see make-efi-image.sh): fstab, network, GRUB on the
# EFI system partition (removable path, no NVRAM), and a kernel command line that starts the
# test init. Usage: guest-efi-setup.sh <Debian mirror>
set -ex
# debootstrap's second stage, which ran just before, unmounts /proc and /sys.
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
MIRROR=${1:?mirror}
ROOT_UUID=$(blkid -s UUID -o value /dev/vda2)
ESP_UUID=$(blkid -s UUID -o value /dev/vda1)
cat > /etc/fstab <<EOF
UUID=$ROOT_UUID / ext4 errors=remount-ro 0 1
UUID=$ESP_UUID /boot/efi vfat umask=0077 0 1
EOF
mount /boot/efi

ip link set lo up
dev=$(ls /sys/class/net | grep -v lo | head -1)
ip link set "$dev" up
ip addr add 10.0.2.15/24 dev "$dev"
ip route add default via 10.0.2.2
echo "nameserver 10.0.2.3" > /etc/resolv.conf
echo "deb $MIRROR trixie main" > /etc/apt/sources.list

apt-get update -q
# This boot has no UEFI runtime (direct kernel boot): no NVRAM entries, use the removable path.
debconf-set-selections <<EOF
grub-efi-arm64 grub2/update_nvram boolean false
grub-efi-arm64 grub2/force_efi_extra_removable boolean true
EOF
DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends grub-efi-arm64
cat > /etc/default/grub.d/ilp32-test.cfg <<EOF
GRUB_TIMEOUT=1
GRUB_TERMINAL=console
GRUB_DISABLE_OS_PROBER=true
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="console=ttyAMA0 panic=-1 init=/ilp32-test/init.sh"
EOF
grub-install --target=arm64-efi --efi-directory=/boot/efi --removable --no-nvram
# The kernel postinst hook only runs update-grub when grub.cfg already exists.
update-grub
ls -R /boot/efi
umount /boot/efi
apt-get clean
echo EFI-SETUP-OK
