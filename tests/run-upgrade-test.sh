#!/bin/bash
# SPDX-License-Identifier: MIT
# Upgrade test from one release to the next on Debian 13 arm64 in QEMU, with throwaway keys and
# file: repositories:
#   v1  the previous release: install ilp32-runtime (runtime only, no kernel), then the kernel
#       metapackage and the compiler
#   v2  the new release: "apt upgrade" upgrades what has a higher version (kernel, runtime,
#       metapackages); packages whose new version is lower (a compiler rebuilt from an older
#       Debian version) follow with the one-time pin and "apt upgrade --allow-downgrades" from
#       the README; then the compiler builds and runs ILP32 programs
#   v3  v2 plus a newer kernel under a new package name (a small stand-in package) and its
#       metapackages: "apt upgrade" must install the new kernel package
# The compiler's host libraries come from a Debian mirror (needs network).
# Needs sudo and an EFI base image from make-efi-image.sh (for the kernel postinst hooks).
# Usage: run-upgrade-test.sh <work dir with efi-base.img> <previous release debs> <new release debs>
#   MIRROR  Debian mirror (default https://deb.debian.org/debian)
set -euo pipefail
WD=$(realpath "${1:?usage: run-upgrade-test.sh <work dir> <previous release debs> <new release debs>}")
OLD=$(realpath "${2:?previous release debs dir}")
NEW=$(realpath "${3:?new release debs dir}")
MIRROR=${MIRROR:-https://deb.debian.org/debian}
HERE=$(dirname "$(realpath "$0")")
TOP=$HERE/..
GUEST=/ilp32-test/repos
cd "$WD"
rm -rf up && mkdir -p up/v1 up/v2 up/v3 up/fake
U=$WD/up

export GNUPGHOME=$U/gnupg
mkdir -m 0700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key "ILP32 Test Key <test@invalid>" ed25519 sign 1d
KEY=$(gpg --with-colons -K test@invalid | awk -F: '/^fpr/ {print $10; exit}')
gpg --armor --export "$KEY" > "$U/test-key.asc"

cp "$OLD"/*.deb "$U/v1/"
cp "$NEW"/*.deb "$U/v2/"
# v3: a stand-in for the next kernel version (new package names) and its metapackages
for p in linux-image-6.12.999-ilp32-arm64 linux-headers-6.12.999-ilp32-arm64; do
	d=$U/fake/$p
	mkdir -p "$d/DEBIAN" "$d/usr/share/doc/$p"
	echo "stand-in for the upgrade test" > "$d/usr/share/doc/$p/README"
	printf 'Package: %s\nVersion: 6.12.999-1+ilp32a64.1\nArchitecture: arm64\nMaintainer: test <test@invalid>\nSection: kernel\nDescription: upgrade test stand-in\n' \
		"$p" > "$d/DEBIAN/control"
	dpkg-deb --root-owner-group --build "$d" "$U/fake/" > /dev/null
done
cp "$U/v2"/*.deb "$U/v3/"
rm "$U"/v3/linux-image-ilp32-arm64_*.deb "$U"/v3/linux-headers-ilp32-arm64_*.deb
cp "$U"/fake/*.deb "$U/v3/"
"$TOP/meta/build-meta-debs.sh" "$U/fake" "$U/fake-meta" > /dev/null
cp "$U"/fake-meta/linux-*-ilp32-arm64_*.deb "$U/v3/"

for v in v1 v2 v3; do
	"$TOP/repo/make-repo.sh" "$U/$v" "$U/repos/$v"
	"$TOP/repo/sign-release.sh" "$U/repos/$v/dists/trixie/Release" "$KEY"
done
KEY_FILE=$U/test-key.asc URIS=file:$GUEST/v1 "$TOP/keyring/build-keyring-deb.sh" "$U/keyring"

# The versions the guest checks, from the packages themselves
ver() { dpkg-deb -f "$(ls "$1"/"$2"_*.deb | head -1)" Version; }
{
	for v in v1 v2; do
		d=$U/$v
		for p in ilp32-runtime libc6-ilp32 libstdc++6-ilp32 linux-image-ilp32-arm64 gcc-14-aarch64-linux-gnu-ilp32; do
			echo "${v}_$(echo "$p" | tr -c 'a-z0-9\n' _)=$(ver "$d" "$p")"
		done
		k=$(ls "$d"/linux-image-6.*-ilp32-arm64_*.deb | head -1)
		echo "${v}_kpkg=$(dpkg-deb -f "$k" Package)"
		echo "${v}_kver=$(dpkg-deb -f "$k" Version)"
	done
	echo "mirror=$MIRROR"
} > "$U/versions"
cat "$U/versions"

cp --sparse=always efi-base.img upgrade-test.img
mkdir -p mnt
LOOP=$(sudo losetup -P --show -f upgrade-test.img)
cleanup() { mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"; sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount "${LOOP}p2" mnt
sudo mkdir -p mnt/ilp32-test
sudo cp -a "$U/repos" "$U/keyring" "$U/versions" mnt/ilp32-test/
sudo cp "$HERE/runtime-test.c" "$HERE/hello++.cc" mnt/ilp32-test/
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
# (! grep would not stop the script: set -e ignores negated commands)
if grep -aq 'RESULT FAIL' upgrade-test.log; then echo "FAILED"; exit 1; fi
echo "upgrade test: all ok"
