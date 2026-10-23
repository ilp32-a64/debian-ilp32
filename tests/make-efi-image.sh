#!/bin/bash
# SPDX-License-Identifier: MIT
# Make a bootable Debian 13 arm64 disk image for the kernel package test: GPT with an EFI system
# partition and an ext4 root, GRUB (grub-efi-arm64, removable path, no NVRAM) and initramfs-tools.
# No kernel is installed; the kernel under test is installed by run-kernel-test.sh.
# Steps: debootstrap stage 1 on the host, then a direct-kernel boot on the ILP32 kernel runs
# stage 2 and installs GRUB from the Debian mirror (needs network). Needs sudo.
# Usage: make-efi-image.sh <work dir>     output: <work dir>/efi-base.img
#   MIRROR  Debian mirror (default https://deb.debian.org/debian)
set -euo pipefail
WD=$(realpath -m "${1:?usage: make-efi-image.sh <work dir>}")
HERE=$(dirname "$(realpath "$0")")
MIRROR=${MIRROR:-https://deb.debian.org/debian}
mkdir -p "$WD"
cd "$WD"
sudo rm -rf rootfs
sudo debootstrap --foreign --arch=arm64 --variant=minbase \
	--include=iproute2,ca-certificates,initramfs-tools,zstd trixie rootfs "$MIRROR"
sudo mkdir -p rootfs/ilp32-test rootfs/boot/efi
sudo install -m 0755 "$HERE/guest-init.sh" rootfs/ilp32-test/init.sh
sudo install -m 0755 "$HERE/guest-efi-setup.sh" rootfs/ilp32-test/guest-efi-setup.sh
printf '#!/bin/bash\n/debootstrap/debootstrap --second-stage && echo SECOND-STAGE-OK\n./guest-efi-setup.sh %s\n' "$MIRROR" |
	sudo tee rootfs/ilp32-test/test.sh > /dev/null
sudo chmod 0755 rootfs/ilp32-test/test.sh

rm -f efi-base.img.tmp
truncate -s 6G efi-base.img.tmp
printf 'label: gpt\nsize=256MiB, type=uefi, name=esp\ntype=linux, name=root\n' | sfdisk -q efi-base.img.tmp
LOOP=$(sudo losetup -P --show -f efi-base.img.tmp)
trap 'sudo losetup -d "$LOOP" 2>/dev/null || true' EXIT
sudo mkfs.vfat -F 32 -n ESP "${LOOP}p1" > /dev/null
sudo mkfs.ext4 -q -F -L ilp32-root -d rootfs "${LOOP}p2"
sudo losetup -d "$LOOP"
trap - EXIT
sudo chown "$(id -u):$(id -g)" efi-base.img.tmp
sudo rm -rf rootfs
ROOT=/dev/vda2 "$HERE/qemu-boot.sh" efi-base.img.tmp | tee efi-base.log
grep -aq SECOND-STAGE-OK efi-base.log
grep -aq EFI-SETUP-OK efi-base.log
mv efi-base.img.tmp efi-base.img
echo "EFI base image: $WD/efi-base.img"
