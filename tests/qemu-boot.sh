#!/bin/bash
# SPDX-License-Identifier: MIT
# Boot a test disk image in QEMU (virt, CPU with PAC and BTI); the guest runs
# /ilp32-test/init.sh and powers off. Console output goes to stdout.
# Usage: qemu-boot.sh <disk image>
#   KERNEL  ILP32 kernel Image given to QEMU directly (default
#           ~/work/test-ilp32/qemu/out/Image-ilp32-6.12.y-pac)
#   ROOT    root device for a direct kernel boot (default /dev/vda)
#   EFI=1   boot through UEFI firmware and the bootloader on the disk instead (no -kernel)
#   EFI_FW  UEFI firmware (default /usr/share/qemu-efi-aarch64/QEMU_EFI.fd)
#   QEMU_SMP, QEMU_MEM, QEMU_TIMEOUT  default 2, 1024 (MB), 3600 (s)
set -u
IMG=${1:?usage: qemu-boot.sh <disk image>}
KERNEL=${KERNEL:-$HOME/work/test-ilp32/qemu/out/Image-ilp32-6.12.y-pac}
if [ "${EFI:-0}" = 1 ]; then
	BOOT=(-bios "${EFI_FW:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}")
else
	BOOT=(-kernel "$KERNEL"
		-append "console=ttyAMA0 root=${ROOT:-/dev/vda} rw panic=-1 init=/ilp32-test/init.sh")
fi
timeout "${QEMU_TIMEOUT:-3600}" qemu-system-aarch64 -M virt -cpu max,pauth-impdef=on \
	-smp "${QEMU_SMP:-2}" -m "${QEMU_MEM:-1024}" -nographic -no-reboot "${BOOT[@]}" \
	-drive file="$IMG",format=raw,if=virtio \
	-netdev user,id=n0 -device virtio-net-pci,netdev=n0 < /dev/null
