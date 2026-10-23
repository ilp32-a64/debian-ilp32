#!/bin/bash
# SPDX-License-Identifier: MIT
# Make a Debian 13 arm64 base disk image for the QEMU tests. debootstrap's first stage runs on
# the host; the second stage runs inside QEMU system emulation on the ILP32 kernel (QEMU user
# mode is not needed). Needs sudo (debootstrap, mkfs.ext4 -d).
# Usage: make-base-image.sh <work dir>    output: <work dir>/base.img
#   KERNEL  ILP32 kernel Image (default ~/work/test-ilp32/qemu/out/Image-ilp32-6.12.y-pac)
#   MIRROR  Debian mirror (default https://deb.debian.org/debian)
set -euo pipefail
WD=$(realpath -m "${1:?usage: make-base-image.sh <work dir>}")
HERE=$(dirname "$(realpath "$0")")
mkdir -p "$WD"
cd "$WD"
sudo rm -rf rootfs
sudo debootstrap --foreign --arch=arm64 --variant=minbase --include=iproute2,ca-certificates \
	trixie rootfs "${MIRROR:-https://deb.debian.org/debian}"
sudo mkdir -p rootfs/ilp32-test
printf '#!/bin/bash\n/debootstrap/debootstrap --second-stage && echo BASE-IMAGE-OK\n' |
	sudo tee rootfs/ilp32-test/test.sh > /dev/null
sudo install -m 0755 "$HERE/guest-init.sh" rootfs/ilp32-test/init.sh
sudo chmod 0755 rootfs/ilp32-test/test.sh
rm -f base.img.tmp
truncate -s 4G base.img.tmp
sudo mkfs.ext4 -q -F -d rootfs base.img.tmp
sudo chown "$(id -u):$(id -g)" base.img.tmp
sudo rm -rf rootfs
"$HERE/qemu-boot.sh" base.img.tmp | tee base-image.log
grep -q BASE-IMAGE-OK base-image.log
mv base.img.tmp base.img
echo "base image: $WD/base.img"
