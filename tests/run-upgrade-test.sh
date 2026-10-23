#!/bin/bash
# SPDX-License-Identifier: MIT
# Upgrade test of the metapackages on Debian 13 arm64 in QEMU, with throwaway keys and file:
# repositories:
#   v1  the release packages + metapackages: "apt install ilp32-runtime" installs the runtime
#       only, "apt install linux-image-ilp32-arm64" the kernel
#   v2  v1 plus a newer kernel under a new package name (a small stand-in package), a rebuilt
#       runtime and newer metapackages: "apt upgrade" must install the new kernel package and
#       upgrade the runtime and the metapackages
# Needs sudo and an EFI base image from make-efi-image.sh (for the kernel postinst hooks).
# Usage: run-upgrade-test.sh <work dir with efi-base.img> <release debs dir>
#   TC  toolchain prefix (default ~/work/ilp32-glibc/toolchain/out)
set -euo pipefail
WD=$(realpath "${1:?usage: run-upgrade-test.sh <work dir> <release debs dir>}")
RDEBS=$(realpath "${2:?release debs dir}")
HERE=$(dirname "$(realpath "$0")")
TOP=$HERE/..
TC=${TC:-$HOME/work/ilp32-glibc/toolchain/out}
T=aarch64-linux-gnu_ilp32
GUEST=/ilp32-test/repos
cd "$WD"
rm -rf up && mkdir -p up/v1 up/v2 up/bin up/fake
U=$WD/up

export GNUPGHOME=$U/gnupg
mkdir -m 0700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key "ILP32 Test Key <test@invalid>" ed25519 sign 1d
KEY=$(gpg --with-colons -K test@invalid | awk -F: '/^fpr/ {print $10; exit}')
gpg --armor --export "$KEY" > "$U/test-key.asc"

# v1: the release and its metapackages
cp "$RDEBS"/*.deb "$U/v1/"
VERSION=2026.10.24 "$TOP/meta/build-meta-debs.sh" "$U/v1" "$U/v1"

# v2: a stand-in for the next kernel version (new package names), its metapackages, a rebuilt
# runtime and a newer ilp32-runtime
for p in linux-image-6.12.999-ilp32-arm64 linux-headers-6.12.999-ilp32-arm64; do
	d=$U/fake/$p
	mkdir -p "$d/DEBIAN" "$d/usr/share/doc/$p"
	echo "stand-in for the upgrade test" > "$d/usr/share/doc/$p/README"
	printf 'Package: %s\nVersion: 6.12.999-1+ilp32a64.1\nArchitecture: arm64\nMaintainer: test <test@invalid>\nSection: kernel\nDescription: upgrade test stand-in\n' \
		"$p" > "$d/DEBIAN/control"
	dpkg-deb --root-owner-group --build "$d" "$U/fake/" > /dev/null
done
cp "$U/v1"/*.deb "$U/v2/"
cp "$U"/fake/*.deb "$U/v2/"
REV=1+ilp32a64.2 "$TOP/runtime/build-debs.sh" "$U/v2"
VERSION=2026.10.25 "$TOP/meta/build-meta-debs.sh" "$U/fake" "$U/v2"

for v in v1 v2; do
	"$TOP/repo/make-repo.sh" "$U/$v" "$U/repos/$v"
	"$TOP/repo/sign-release.sh" "$U/repos/$v/dists/trixie/Release" "$KEY"
done
KEY_FILE=$U/test-key.asc URIS=file:$GUEST/v1 "$TOP/keyring/build-keyring-deb.sh" "$U/keyring"

"$TC/bin/$T-gcc" -O2 -fopenmp -o "$U/bin/runtime-test" "$HERE/runtime-test.c" -lm -latomic

cp --sparse=always efi-base.img upgrade-test.img
mkdir -p mnt
LOOP=$(sudo losetup -P --show -f upgrade-test.img)
cleanup() { mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"; sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount "${LOOP}p2" mnt
sudo mkdir -p mnt/ilp32-test
sudo cp -a "$U/repos" "$U/bin" "$U/keyring" mnt/ilp32-test/
sudo chown -R root:root mnt/ilp32-test
sudo install -m 0755 "$HERE/guest-upgrade-test.sh" mnt/ilp32-test/guest-upgrade-test.sh
printf '#!/bin/bash\n./guest-upgrade-test.sh\n' | sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
sudo losetup -d "$LOOP"
trap - EXIT

ROOT=/dev/vda2 "$HERE/qemu-boot.sh" upgrade-test.img | tee upgrade-test.log
grep -a -E '^(===|RESULT|INFO)' upgrade-test.log
grep -aq ILP32-TEST-END upgrade-test.log
! grep -aq 'RESULT FAIL' upgrade-test.log
echo "upgrade test: all ok"
