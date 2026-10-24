#!/bin/bash
# SPDX-License-Identifier: MIT
# Create the Debian 13 (trixie) amd64 chroot that build-deb.sh runs in (through chroot-run.sh): Debian's
# cross toolchain for arm64 and armhf (gcc-14, binutils), pahole for BTF, the kernel build and packaging
# tools, and libssl-dev:arm64 (multiarch) for the arm64 sign-file of linux-headers. Needs sudo and
# debootstrap.
#
# Usage: setup-chroot.sh
#   CHROOT  chroot directory (default ~/work/debian13-kbuild/chroot)
#   MIRROR  Debian mirror (default http://deb.debian.org/debian)
set -euo pipefail
umask 022
C=${CHROOT:-$HOME/work/debian13-kbuild/chroot}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
[ ! -e "$C" ] || { echo "$C exists"; exit 1; }
mkdir -p "$(dirname "$C")"
sudo debootstrap --variant=buildd \
	--include=git,bc,bison,flex,kmod,cpio,rsync,xz-utils,zstd,python3,file,passwd,pkgconf,debhelper,fakeroot,dpkg-dev,libssl-dev,libelf-dev,dwarves,gcc-14-aarch64-linux-gnu,gcc-aarch64-linux-gnu,binutils-aarch64-linux-gnu,gcc-14-arm-linux-gnueabihf,gcc-arm-linux-gnueabihf,binutils-arm-linux-gnueabihf,crossbuild-essential-arm64 \
	trixie "$C" "$MIRROR"
sudo chroot "$C" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive sh -e -c '
	dpkg --add-architecture arm64
	apt-get -q update
	apt-get -qy install --no-install-recommends libssl-dev:arm64
'
sudo chroot "$C" sh -c 'aarch64-linux-gnu-gcc-14 --version | head -1; aarch64-linux-gnu-ld --version | head -1; pahole --version'
