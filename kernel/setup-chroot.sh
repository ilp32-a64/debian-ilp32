#!/bin/bash
# SPDX-License-Identifier: MIT
# Create the Debian 13 (trixie) amd64 build environment of build-deb.sh: Debian's cross toolchain for
# arm64 and armhf (gcc-14, binutils), pahole for BTF, the kernel build and packaging tools, and
# libssl-dev:arm64 (multiarch) for the arm64 sign-file of linux-headers; trixie, trixie-updates and
# trixie-security, upgraded. The result is saved as a pristine base tarball (BASE): release builds run
# in a fresh copy of it (chroot-run.sh --fresh), so nothing of earlier builds or other users is in them.
# The same tree becomes the long-lived chroot (CHROOT) for development builds if there is none yet.
# Needs sudo, debootstrap and zstd.
#
# Usage: setup-chroot.sh
#   BASE    base tarball (default ~/work/debian13-kbuild/base.tar.zst; replaced)
#   CHROOT  long-lived chroot (default ~/work/debian13-kbuild/chroot; left alone if it exists)
#   MIRROR  Debian mirror (default http://deb.debian.org/debian)
set -euo pipefail
umask 022
D=$(dirname "$(realpath "$0")")
BASE=${BASE:-$HOME/work/debian13-kbuild/base.tar.zst}
C=${CHROOT:-$HOME/work/debian13-kbuild/chroot}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
mkdir -p "$(dirname "$BASE")" "$(dirname "$C")"
T=$(mktemp -d "$(dirname "$BASE")/setup.XXXXXX")
sudo debootstrap --variant=buildd \
	--include=git,openssl,bc,bison,flex,kmod,cpio,rsync,xz-utils,zstd,python3,file,passwd,pkgconf,debhelper,fakeroot,dpkg-dev,libssl-dev,libelf-dev,dwarves,gcc-14-aarch64-linux-gnu,gcc-aarch64-linux-gnu,binutils-aarch64-linux-gnu,gcc-14-arm-linux-gnueabihf,gcc-arm-linux-gnueabihf,binutils-arm-linux-gnueabihf,crossbuild-essential-arm64 \
	trixie "$T" "$MIRROR"
sudo chroot "$T" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive \
	MIRROR="$MIRROR" sh -e -c '
	printf "%s\n" "deb $MIRROR trixie main" "deb $MIRROR trixie-updates main" \
		"deb http://security.debian.org/debian-security trixie-security main" > /etc/apt/sources.list
	dpkg --add-architecture arm64
	apt-get -q update
	apt-get -qy dist-upgrade
	apt-get -qy install --no-install-recommends libssl-dev:arm64
	apt-get clean
	rm -rf /var/lib/apt/lists/*
'
sudo chroot "$T" sh -c 'aarch64-linux-gnu-gcc-14 --version | head -1; aarch64-linux-gnu-ld --version | head -1; pahole --version'
# nothing may be mounted in the tree that is packed or removed
[ -z "$(findmnt -rn -o TARGET | grep -F "$T")" ] || { echo "ERROR: mounts under $T"; exit 1; }
sudo tar -C "$T" --numeric-owner --xattrs -cf - . | zstd -q -T0 -o "$BASE.new"
mv "$BASE.new" "$BASE"
echo "==> $BASE: $(sha256sum "$BASE" | cut -c1-16)…, $(du -h "$BASE" | cut -f1)"
if [ -e "$C" ]; then
	sudo rm -rf --one-file-system "$T"
	echo "==> $C exists: left as it is (development builds)"
else
	sudo mv "$T" "$C"
	echo "==> $C: long-lived chroot for development builds"
fi
