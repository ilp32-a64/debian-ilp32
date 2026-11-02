#!/bin/bash
# SPDX-License-Identifier: MIT
# Python test on Debian 13 arm64 in QEMU: install the ILP32 runtime, compiler and CPython set with
# apt (Debian's python3-pip comes from a Debian mirror; needs network), check the interpreter,
# its modules and libraries, a C extension and pip's platform tags (guest-python-test.sh).
# Needs sudo (loop mount) and the base image from make-base-image.sh.
# Usage: run-python-test.sh <work dir with base.img> <dir with the .debs>
#   MIRROR  Debian mirror (default https://deb.debian.org/debian)
set -euo pipefail
MIRROR=${MIRROR:-https://deb.debian.org/debian}
WD=$(realpath "${1:?usage: run-python-test.sh <work dir> <debs dir>}")
DEBS=$(realpath "${2:?debs dir}")
HERE=$(dirname "$(realpath "$0")")
cd "$WD"
cp --sparse=always base.img python-test.img
# room for the CPython set
truncate -s +3G python-test.img
e2fsck -fp python-test.img > /dev/null || true
resize2fs python-test.img > /dev/null
mkdir -p mnt
sudo mount -o loop python-test.img mnt
trap 'mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"' EXIT
sudo mkdir -p mnt/ilp32-test/debs
sudo cp "$DEBS"/*.deb mnt/ilp32-test/debs/
sudo install -m 0755 "$HERE/guest-python-test.sh" mnt/ilp32-test/guest-python-test.sh
printf '#!/bin/bash\n./guest-python-test.sh %s\n' "$MIRROR" | sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
"$HERE/qemu-boot.sh" python-test.img | tee python-test.log
grep -a -E '^(===|RESULT|INFO)' python-test.log
grep -aq ILP32-TEST-END python-test.log
# (! grep would not stop the script: set -e ignores negated commands)
if grep -aq 'RESULT FAIL' python-test.log; then echo "FAILED"; exit 1; fi
echo "python test: all ok"
