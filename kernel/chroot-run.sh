#!/bin/bash
# SPDX-License-Identifier: MIT
# Run a command as the calling user inside the Debian 13 build chroot of setup-chroot.sh, with ~/work
# bind-mounted at the same path (the kernel trees, the build directory and the output are under it).
# Creates the user in the chroot (same uid and gid) on first use. The mounts are made for the command
# and removed when it ends, so that the chroot directory never holds a live view of ~/work (a recursive
# delete of the chroot would go into it, and du would count ~/work twice). ~/work is bind-mounted as a
# slave: mounts made under it later do not propagate back. Needs sudo; one run per chroot at a time.
#
# Usage: chroot-run.sh <command> [args...]
#   CHROOT  chroot directory (default ~/work/debian13-kbuild/chroot)
#   WORK    directory to bind-mount (default ~/work)
set -euo pipefail
C=${CHROOT:-$HOME/work/debian13-kbuild/chroot}
WORK=${WORK:-$HOME/work}
U=$(id -un) G=$(id -gn)
[ -x "$C/usr/bin/aarch64-linux-gnu-gcc-14" ] || { echo "no build chroot in $C: run setup-chroot.sh"; exit 1; }
for m in /proc /dev/pts /dev "$WORK"; do
	! mountpoint -q "$C$m" || { echo "$C$m is mounted: another chroot-run.sh, or left over (sudo umount -R $C$m)"; exit 1; }
done
if ! sudo chroot "$C" getent passwd "$U" > /dev/null; then
	sudo chroot "$C" /usr/sbin/groupadd -g "$(id -g)" "$G"
	sudo chroot "$C" /usr/sbin/useradd -u "$(id -u)" -g "$(id -g)" -d "$HOME" -M -s /bin/bash "$U"
fi
umount_all() {
	for m in "$WORK" /dev/pts /dev /proc; do
		! mountpoint -q "$C$m" || sudo umount -R "$C$m"
	done
}
trap umount_all EXIT
sudo mkdir -p "$C$WORK"
sudo mount -t proc proc "$C/proc"
sudo mount --bind /dev "$C/dev"
sudo mount --bind /dev/pts "$C/dev/pts"
sudo mount --bind "$WORK" "$C$WORK"
sudo mount --make-rslave "$C$WORK"
sudo chroot --userspec="$U:$G" "$C" /usr/bin/env -i HOME="$HOME" USER="$U" LANG=C.UTF-8 \
	PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin "$@"
