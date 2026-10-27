#!/bin/bash
# SPDX-License-Identifier: MIT
# Run a command as the calling user inside a Debian 13 build chroot of setup-chroot.sh, with ~/work
# bind-mounted at the same path (the kernel trees, the build directory and the output are under it).
# - default: the long-lived chroot (CHROOT), for development builds
# - --fresh: a fresh copy of the pristine base tarball (BASE), removed after the command; for builds whose
#   output is released. The command gets BUILD_CHROOT, which names the base and its sha256 (build-deb.sh
#   records it with the package list).
# Creates the user in the chroot (same uid and gid). The mounts are made for the command and removed when
# it ends, so that the chroot directory never holds a live view of ~/work (a recursive delete of the
# chroot would go into it, and du would count ~/work twice). ~/work is bind-mounted as a slave: mounts
# made under it later do not propagate back. Needs sudo (and zstd for --fresh); one run per long-lived
# chroot at a time, any number of fresh ones.
#
# Usage: chroot-run.sh [--fresh] <command> [args...]
#   CHROOT  long-lived chroot (default ~/work/debian13-kbuild/chroot)
#   BASE    base tarball for --fresh (default ~/work/debian13-kbuild/base.tar.zst)
#   WORK    directory to bind-mount (default ~/work)
set -euo pipefail
C=${CHROOT:-$HOME/work/debian13-kbuild/chroot}
BASE=${BASE:-$HOME/work/debian13-kbuild/base.tar.zst}
WORK=${WORK:-$HOME/work}
U=$(id -un) G=$(id -gn)
FRESH=
if [ "${1:-}" = --fresh ]; then
	shift
	[ -f "$BASE" ] || { echo "no base tarball $BASE: run setup-chroot.sh"; exit 1; }
	FRESH=$(mktemp -d "$(dirname "$BASE")/fresh.XXXXXX")
	C=$FRESH
	BUILD_CHROOT="fresh copy of $(basename "$BASE") (sha256 $(sha256sum "$BASE" | cut -d' ' -f1))"
	zstd -q -dc "$BASE" | sudo tar -C "$C" --numeric-owner --xattrs -xf -
else
	BUILD_CHROOT="long-lived chroot $C"
fi
[ -x "$C/usr/bin/aarch64-linux-gnu-gcc-14" ] || { echo "no build chroot in $C: run setup-chroot.sh"; exit 1; }
for m in /proc /dev/pts /dev "$WORK"; do
	! mountpoint -q "$C$m" || { echo "$C$m is mounted: another chroot-run.sh, or left over (sudo umount -R $C$m)"; exit 1; }
done
if ! sudo chroot "$C" getent passwd "$U" > /dev/null; then
	sudo chroot "$C" /usr/sbin/groupadd -g "$(id -g)" "$G"
	sudo chroot "$C" /usr/sbin/useradd -u "$(id -u)" -g "$(id -g)" -d "$HOME" -M -s /bin/bash "$U"
fi
cleanup() {
	for m in "$WORK" /dev/pts /dev /proc; do
		! mountpoint -q "$C$m" || sudo umount -R "$C$m" || sudo umount -lR "$C$m"
	done
	if [ -n "$FRESH" ]; then
		# only with nothing mounted under it: never delete through a mount
		if [ -z "$(findmnt -rn -o TARGET | grep -F "$FRESH")" ]; then
			sudo rm -rf --one-file-system "$FRESH"
		else
			echo "WARNING: mounts left under $FRESH, not removed"
		fi
	fi
}
trap cleanup EXIT
sudo mkdir -p "$C$WORK"
sudo mount -t proc proc "$C/proc"
sudo mount --bind /dev "$C/dev"
sudo mount --bind /dev/pts "$C/dev/pts"
sudo mount --bind "$WORK" "$C$WORK"
sudo mount --make-rslave "$C$WORK"
sudo chroot --userspec="$U:$G" "$C" /usr/bin/env -i HOME="$HOME" USER="$U" LANG=C.UTF-8 \
	PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin BUILD_CHROOT="$BUILD_CHROOT" "$@"
