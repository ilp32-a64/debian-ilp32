#!/bin/bash
# SPDX-License-Identifier: MIT
# Toolchain test on Debian 13 arm64 in QEMU: install the runtime and the on-board ILP32 compiler
# packages, build C, C++, OpenMP, static, shared and LTO programs on the guest and run them.
# Needs sudo (loop mount) and the base image from make-base-image.sh.
# Usage: run-toolchain-test.sh <work dir with base.img> <dir with runtime and toolchain .debs>
set -euo pipefail
WD=$(realpath "${1:?usage: run-toolchain-test.sh <work dir> <debs dir>}")
DEBS=$(realpath "${2:?debs dir}")
HERE=$(dirname "$(realpath "$0")")
cd "$WD"
cp --sparse=always base.img toolchain-test.img
mkdir -p mnt
sudo mount -o loop toolchain-test.img mnt
trap 'mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"' EXIT
sudo mkdir -p mnt/ilp32-test/debs mnt/ilp32-test/src
sudo cp "$DEBS"/*.deb mnt/ilp32-test/debs/
sudo cp "$HERE/hello.c" "$HERE/hello++.cc" "$HERE/runtime-test.c" mnt/ilp32-test/src/
sudo install -m 0755 "$HERE/guest-toolchain-test.sh" mnt/ilp32-test/guest-toolchain-test.sh
printf '#!/bin/bash\n./guest-toolchain-test.sh\n' | sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
"$HERE/qemu-boot.sh" toolchain-test.img | tee toolchain-test.log
grep -a -E '^(===|RESULT)' toolchain-test.log
grep -aq ILP32-TEST-END toolchain-test.log
if grep -aq 'RESULT FAIL' toolchain-test.log; then echo "FAILED"; exit 1; fi
echo "toolchain test: all ok"
