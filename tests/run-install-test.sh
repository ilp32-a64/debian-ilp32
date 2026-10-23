#!/bin/bash
# SPDX-License-Identifier: MIT
# Install test of the runtime packages on Debian 13 arm64 in QEMU: build the ILP32 test
# programs, copy the base image, add the packages and programs, boot, and check the result;
# then scan the packages for internal information (scan-leaks.sh).
# Needs sudo (loop mount).
# Usage: run-install-test.sh <work dir with base.img> <dir with *.deb>
#   TC  toolchain prefix (default ~/work/ilp32-glibc/toolchain/out)
set -euo pipefail
WD=$(realpath "${1:?usage: run-install-test.sh <work dir> <debs dir>}")
DEBS=$(realpath "${2:?usage: run-install-test.sh <work dir> <debs dir>}")
HERE=$(dirname "$(realpath "$0")")
TC=${TC:-$HOME/work/ilp32-glibc/toolchain/out}
T=aarch64-linux-gnu_ilp32
cd "$WD"
rm -rf bin && mkdir bin
"$TC/bin/$T-gcc" -O2 -o bin/hello-ilp32 "$HERE/hello.c"
"$TC/bin/$T-g++" -O2 -o bin/hello++-ilp32 "$HERE/hello++.cc"
"$TC/bin/$T-gcc" -O2 -fopenmp -o bin/runtime-test "$HERE/runtime-test.c" -lm -latomic
cp --sparse=always base.img test.img
mkdir -p mnt
sudo mount -o loop test.img mnt
trap 'mountpoint -q mnt && sudo umount mnt' EXIT
sudo mkdir -p mnt/ilp32-test/debs mnt/ilp32-test/bin
sudo cp "$DEBS"/*.deb mnt/ilp32-test/debs/
sudo cp bin/* mnt/ilp32-test/bin/
sudo install -m 0755 "$HERE/guest-install-test.sh" mnt/ilp32-test/guest-install-test.sh
printf '#!/bin/bash\n./guest-install-test.sh /ilp32-test/debs /ilp32-test/bin\n' |
	sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
"$HERE/qemu-boot.sh" test.img | tee install-test.log
grep -a -E '^(===|RESULT)' install-test.log
grep -aq ILP32-TEST-END install-test.log
! grep -aq 'RESULT FAIL' install-test.log
echo "install test: all ok"
"$HERE/scan-leaks.sh" "$DEBS"
