#!/bin/bash
# SPDX-License-Identifier: MIT
# Run a command as the calling user inside the Debian 13 build chroot of setup-chroot.sh, with ~/work
# bind-mounted at the same path (the kernel trees, the build directory and the output are under it).
# Creates the user in the chroot (same uid and gid) and the mounts on first use. Needs sudo.
#
# Usage: chroot-run.sh <command> [args...]
#   CHROOT  chroot directory (default ~/work/debian13-kbuild/chroot)
#   WORK    directory to bind-mount (default ~/work)
set -euo pipefail
C=${CHROOT:-$HOME/work/debian13-kbuild/chroot}
WORK=${WORK:-$HOME/work}
U=$(id -un) G=$(id -gn)
[ -x "$C/usr/bin/aarch64-linux-gnu-gcc-14" ] || { echo "no build chroot in $C: run setup-chroot.sh"; exit 1; }
if ! sudo chroot "$C" getent passwd "$U" > /dev/null; then
	sudo chroot "$C" /usr/sbin/groupadd -g "$(id -g)" "$G"
	sudo chroot "$C" /usr/sbin/useradd -u "$(id -u)" -g "$(id -g)" -d "$HOME" -M -s /bin/bash "$U"
fi
mnt() { mountpoint -q "$C$2" || { sudo mkdir -p "$C$2"; sudo mount "${@:3}" "$1" "$C$2"; }; }
mnt proc /proc -t proc
mnt /dev /dev --bind
mnt /dev/pts /dev/pts --bind
mnt "$WORK" "$WORK" --bind
exec sudo chroot --userspec="$U:$G" "$C" /usr/bin/env -i HOME="$HOME" USER="$U" LANG=C.UTF-8 \
	PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin "$@"
