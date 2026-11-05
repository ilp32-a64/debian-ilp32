#!/bin/bash
# SPDX-License-Identifier: MIT
# Test of the default boot kernel (meta/boot-default) on Debian 13 arm64 in QEMU, with real Debian
# kernels on both sides of ours from the Debian mirrors (needs network). GRUB is booted through
# UEFI; extlinux and raspi-firmware are checked at the level of their generated files, since QEMU
# does not run those loaders here (see the boards for that).
#   boot 1  direct kernel: without the package the higher Debian kernel is the default; with it the
#           ILP32 kernel stays the default when a higher Debian kernel is installed
#   boot 2  UEFI -> GRUB: runs the ILP32 kernel, and an ILP32 program runs
#   boot 3  direct kernel: off switch, grub.cfg identical to one from a system without the package
#   boot 4  UEFI -> GRUB: runs Debian's kernel, and an ILP32 program is refused
#   boot 5  direct kernel: guards, removal and purge in both orders, extlinux, raspi-firmware
# The base image is only read: the guest writes to a qcow2 overlay. Needs sudo (qemu-nbd).
# Usage: run-boot-default-test.sh <efi-base.img> <work dir> <debs dir>
#   the debs dir has the kernel package and the metapackage under test
#   LOW, HIGH  Debian kernel releases below and above the ILP32 kernel
#   TC  toolchain prefix (default ~/work/ilp32-glibc/toolchain/out)
set -euo pipefail
BASE=$(realpath "${1:?usage: run-boot-default-test.sh <efi-base.img> <work dir> <debs dir>}")
WD=$(realpath -m "${2:?work dir}")
DEBS=$(realpath "${3:?debs dir}")
HERE=$(dirname "$(realpath "$0")")
TC=${TC:-$HOME/work/ilp32-glibc/toolchain/out}
LOW=${LOW:-6.12.107+deb13-arm64}
HIGH=${HIGH:-6.12.115+deb13.1-arm64}
NBD=${NBD:-/dev/nbd7}
MIN_FREE_KB=${MIN_FREE_KB:-2500000}
mkdir -p "$WD/mnt"
cd "$WD"
free=$(df -Pk . | awk 'END { print $4 }')
if [ "$free" -lt "$MIN_FREE_KB" ]; then
	echo "only $free kB free, need $MIN_FREE_KB: the guest's overlay grows by about 2 GB"
	exit 1
fi

KIMG=$(ls "$DEBS"/linux-image-*-ilp32-arm64_*.deb | grep -v -- -dbg_ | head -1)
META=$(ls "$DEBS"/linux-image-ilp32-arm64_*.deb | head -1)
ILP32=$(dpkg-deb -f "$KIMG" Package | sed 's/^linux-image-//')
echo "kernel $(basename "$KIMG"), metapackage $(basename "$META"), Debian $LOW and $HIGH"
"$TC/bin/aarch64-linux-gnu_ilp32-gcc" -O2 -static -o hello-ilp32 "$HERE/hello.c"

rm -f boot-default.qcow2
qemu-img create -q -f qcow2 -F raw -b "$BASE" boot-default.qcow2
sudo modprobe nbd max_part=8
cleanup() {
	mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"
	sudo qemu-nbd -d "$NBD" > /dev/null 2>&1 || true
}
trap cleanup EXIT
sudo qemu-nbd -c "$NBD" -f qcow2 boot-default.qcow2
for _ in $(seq 20); do [ -e "${NBD}p2" ] && break; sleep 0.5; done
sudo mount "${NBD}p2" mnt
sudo mkdir -p mnt/ilp32-test/debs
sudo cp "$KIMG" "$META" mnt/ilp32-test/debs/
sudo install -m 0755 hello-ilp32 mnt/ilp32-test/hello-ilp32
sudo install -m 0755 "$HERE/guest-boot-default-test.sh" mnt/ilp32-test/guest-boot-default-test.sh
printf 'ILP32=%s\nLOW=%s\nHIGH=%s\nIMG=/ilp32-test/debs/%s\nMETA=/ilp32-test/debs/%s\n' \
	"$ILP32" "$LOW" "$HIGH" "$(basename "$KIMG")" "$(basename "$META")" | sudo tee mnt/ilp32-test/versions > /dev/null
echo install | sudo tee mnt/ilp32-test/phase > /dev/null
printf '#!/bin/bash\n./guest-boot-default-test.sh\n' | sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
sudo qemu-nbd -d "$NBD" > /dev/null
trap - EXIT

export IMG_FORMAT=qcow2 QEMU_MEM=${QEMU_MEM:-3072} QEMU_TIMEOUT=${QEMU_TIMEOUT:-10800}
n=0
boot() {
	n=$((n + 1))
	echo "=== boot $n: $1"
	if [ "$1" = efi ]; then
		EFI=1 "$HERE/qemu-boot.sh" boot-default.qcow2 > "boot-default-$n.log" 2>&1 || true
	else
		ROOT=/dev/vda2 "$HERE/qemu-boot.sh" boot-default.qcow2 > "boot-default-$n.log" 2>&1 || true
	fi
	grep -a -E '^(===|RESULT|INFO)' "boot-default-$n.log" || true
	grep -aq ILP32-TEST-END "boot-default-$n.log" || { echo "boot $n did not finish"; exit 1; }
}
boot direct
boot efi
boot direct
boot efi
boot direct
# (! grep would not stop the script: set -e ignores negated commands)
if grep -aq 'RESULT FAIL' boot-default-*.log; then
	echo "FAILED:"
	grep -a 'RESULT FAIL' boot-default-*.log
	exit 1
fi
grep -aq BOOT-DEFAULT-DONE "boot-default-$n.log"
echo "overlay: $(du -sh boot-default.qcow2 | cut -f1)"
echo "boot default test: all ok"
