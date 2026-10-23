#!/bin/bash
# SPDX-License-Identifier: MIT
# Kernel package test: install the kernel .deb in Debian 13 arm64 like a user would (dpkg -i,
# initramfs and GRUB hooks), boot it through UEFI firmware and GRUB, then install the ILP32
# runtime packages and run the runtime tests on the installed kernel.
#   boot 1  direct kernel boot (test kernel): dpkg -i linux-image-*.deb, check /boot and grub.cfg
#   boot 2  UEFI -> GRUB -> installed kernel + initramfs: check the kernel, run guest-install-test.sh
# Needs sudo (loop mount) and an EFI base image from make-efi-image.sh.
# Usage: run-kernel-test.sh <work dir with efi-base.img> <kernel debs dir> <runtime debs dir>
#   EXPECT_RELEASE  expected uname -r (default: from the linux-image package name)
#   EXPECT_ILP32=0  the kernel under test has no ILP32 (e.g. Debian's own, to check the test itself)
#   TC  toolchain prefix (default ~/work/ilp32-glibc/toolchain/out)
set -euo pipefail
WD=$(realpath "${1:?usage: run-kernel-test.sh <work dir> <kernel debs> <runtime debs>}")
KDEBS=$(realpath "${2:?kernel debs dir}")
RDEBS=$(realpath "${3:?runtime debs dir}")
HERE=$(dirname "$(realpath "$0")")
TC=${TC:-$HOME/work/ilp32-glibc/toolchain/out}
T=aarch64-linux-gnu_ilp32
cd "$WD"
KIMG=$(ls "$KDEBS"/linux-image-*.deb | grep -v -- -dbg_ | head -1)
EXPECT_RELEASE=${EXPECT_RELEASE:-$(dpkg-deb -f "$KIMG" Package | sed 's/^linux-image-//')}
echo "kernel package: $(basename "$KIMG"), expected release $EXPECT_RELEASE"

rm -rf kt && mkdir -p kt/bin
"$TC/bin/$T-gcc" -O2 -o kt/bin/hello-ilp32 "$HERE/hello.c"
"$TC/bin/$T-g++" -O2 -o kt/bin/hello++-ilp32 "$HERE/hello++.cc"
"$TC/bin/$T-gcc" -O2 -fopenmp -o kt/bin/runtime-test "$HERE/runtime-test.c" -lm -latomic

cp --sparse=always efi-base.img kernel-test.img
mkdir -p mnt
LOOP=$(sudo losetup -P --show -f kernel-test.img)
cleanup() { mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"; sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount "${LOOP}p2" mnt
sudo mkdir -p mnt/ilp32-test/kdebs mnt/ilp32-test/debs mnt/ilp32-test/bin
sudo cp "$KIMG" mnt/ilp32-test/kdebs/
sudo cp "$RDEBS"/*.deb mnt/ilp32-test/debs/
sudo cp kt/bin/* mnt/ilp32-test/bin/
for f in guest-kernel-test.sh guest-install-test.sh; do
	sudo install -m 0755 "$HERE/$f" mnt/ilp32-test/$f
done
printf '#!/bin/bash\n./guest-kernel-test.sh install %s %s\n' "$EXPECT_RELEASE" "${EXPECT_ILP32:-1}" |
	sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
sudo losetup -d "$LOOP"

echo "=== boot 1: install the kernel package"
ROOT=/dev/vda2 "$HERE/qemu-boot.sh" kernel-test.img | tee kernel-test-1.log
grep -aq 'KERNEL-INSTALL-OK' kernel-test-1.log

echo "=== boot 2: UEFI -> GRUB -> installed kernel"
EFI=1 "$HERE/qemu-boot.sh" kernel-test.img | tee kernel-test-2.log
grep -a -E '^(===|RESULT)' kernel-test-1.log kernel-test-2.log
grep -aq ILP32-TEST-END kernel-test-2.log
! grep -aq 'RESULT FAIL' kernel-test-1.log kernel-test-2.log
echo "kernel test: all ok"
