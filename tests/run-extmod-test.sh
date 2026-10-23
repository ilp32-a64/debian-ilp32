#!/bin/bash
# SPDX-License-Identifier: MIT
# External module test of the kernel headers package (as DKMS uses it): install the kernel and
# headers packages (gcc and make come as their dependencies), boot the kernel through UEFI and
# GRUB, build a small module against /lib/modules/<release>/build, load and unload it.
#   boot 1  direct kernel boot (test kernel): apt install of the kernel and headers packages,
#           which pulls in gcc and make from the Debian mirror (needs network)
#   boot 2  UEFI -> GRUB -> installed kernel: build, insmod, rmmod
# Needs sudo and an EFI base image from make-efi-image.sh.
# Usage: run-extmod-test.sh <work dir with efi-base.img> <kernel debs dir>
#   MIRROR  Debian mirror (default https://deb.debian.org/debian)
set -euo pipefail
WD=$(realpath "${1:?usage: run-extmod-test.sh <work dir> <kernel debs dir>}")
KDEBS=$(realpath "${2:?kernel debs dir}")
HERE=$(dirname "$(realpath "$0")")
MIRROR=${MIRROR:-https://deb.debian.org/debian}
cd "$WD"
KIMG=$(ls "$KDEBS"/linux-image-*-ilp32-arm64_*.deb | grep -v -e -dbg_ -e linux-image-ilp32-arm64_ | head -1)
KHDR=$(ls "$KDEBS"/linux-headers-*-ilp32-arm64_*.deb | grep -v linux-headers-ilp32-arm64_ | head -1)
REL=$(dpkg-deb -f "$KIMG" Package | sed 's/^linux-image-//')
echo "kernel $REL"

cp --sparse=always efi-base.img extmod-test.img
mkdir -p mnt
LOOP=$(sudo losetup -P --show -f extmod-test.img)
cleanup() { mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"; sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount "${LOOP}p2" mnt
sudo mkdir -p mnt/ilp32-test/kdebs
sudo cp "$KIMG" "$KHDR" mnt/ilp32-test/kdebs/
sudo install -m 0755 "$HERE/guest-extmod-test.sh" mnt/ilp32-test/guest-extmod-test.sh
printf '#!/bin/bash\n./guest-extmod-test.sh install %s %s\n' "$REL" "$MIRROR" |
	sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
sudo losetup -d "$LOOP"
trap - EXIT

echo "=== boot 1: install the kernel and headers, gcc and make"
ROOT=/dev/vda2 "$HERE/qemu-boot.sh" extmod-test.img | tee extmod-test-1.log
grep -aq 'EXTMOD-INSTALL-OK' extmod-test-1.log
echo "=== boot 2: build and load a module on the installed kernel"
EFI=1 "$HERE/qemu-boot.sh" extmod-test.img | tee extmod-test-2.log
grep -a -E '^(===|RESULT|INFO)' extmod-test-1.log extmod-test-2.log
grep -aq ILP32-TEST-END extmod-test-2.log
# (! grep would not stop the script: set -e ignores negated commands)
if grep -aq 'RESULT FAIL' extmod-test-1.log extmod-test-2.log; then echo "FAILED"; exit 1; fi
echo "external module test: all ok"
