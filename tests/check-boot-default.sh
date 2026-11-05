#!/bin/bash
# SPDX-License-Identifier: MIT
# Checks of meta/boot-default that need no VM: every file parses as POSIX sh, and the fragments that
# other tools source under "set -e" neither stop them nor change their arguments, with select
# absent, printing nothing, printing a release, or failing. Uses a private copy of the fragments
# with the path of select replaced.
set -u
HERE=$(dirname "$(realpath "$0")")
SRC=$HERE/../meta/boot-default
ROOT=$SRC/root
fail=0
ok() { echo "RESULT ok: $*"; }
bad() { echo "RESULT FAIL: $*"; fail=1; }

SCRIPTS=(usr/lib/ilp32-kernel/select usr/lib/ilp32-kernel/raspi-apply usr/sbin/ilp32-kernel-update-boot
	etc/default/grub.d/ilp32-kernel.cfg usr/share/u-boot-menu/conf.d/ilp32-kernel.conf
	etc/kernel/postinst.d/zz-ilp32-kernel etc/kernel/postrm.d/zz-ilp32-kernel
	etc/initramfs/post-update.d/zz-ilp32-kernel etc/default/ilp32-kernel)
for f in "${SCRIPTS[@]}"; do
	if dash -n "$ROOT/$f"; then ok "dash -n $f"; else bad "dash -n $f"; fi
	[ -e "$ROOT/$f" ] || bad "missing $f"
done
for f in postinst prerm postrm; do
	if dash -n "$SRC/DEBIAN/$f"; then ok "dash -n DEBIAN/$f"; else bad "dash -n DEBIAN/$f"; fi
done
for f in usr/lib/ilp32-kernel/select usr/lib/ilp32-kernel/raspi-apply usr/sbin/ilp32-kernel-update-boot \
	etc/kernel/postinst.d/zz-ilp32-kernel etc/kernel/postrm.d/zz-ilp32-kernel \
	etc/initramfs/post-update.d/zz-ilp32-kernel; do
	if [ -x "$ROOT/$f" ]; then ok "executable $f"; else bad "not executable $f"; fi
done
if grep -rlU $'\r' "$SRC" "$HERE/check-boot-default.sh" > /dev/null; then bad "CR in a file"; else ok "no CR"; fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/sel"
# fragment <file> <select contents, or "absent"> <variable> <expected value>
fragment() {
	local file=$1 body=$2 var=$3 want=$4 got
	rm -f "$W/sel/select"
	if [ "$body" != absent ]; then
		printf '#!/bin/sh\n%s\n' "$body" > "$W/sel/select"
		chmod +x "$W/sel/select"
	fi
	sed "s,/usr/lib/ilp32-kernel/select,$W/sel/select,g" "$ROOT/$file" > "$W/frag"
	got=$(dash -e -c '. "$0"; echo "reached:$1:$(eval echo \$'"$var"')"' "$W/frag" keep 2>&1)
	if [ "$got" = "reached:keep:$want" ]; then
		ok "$file with select: $body -> '$want'"
	else
		bad "$file with select: $body: got '$got', want 'reached:keep:$want'"
	fi
}
G=etc/default/grub.d/ilp32-kernel.cfg
U=usr/share/u-boot-menu/conf.d/ilp32-kernel.conf
fragment "$G" absent GRUB_TOP_LEVEL ""
fragment "$G" "exit 0" GRUB_TOP_LEVEL ""
fragment "$G" "exit 3" GRUB_TOP_LEVEL ""
fragment "$G" "echo 6.12.1-ilp32-arm64" GRUB_TOP_LEVEL /boot/vmlinuz-6.12.1-ilp32-arm64
fragment "$U" absent U_BOOT_DEFAULT ""
fragment "$U" "exit 0" U_BOOT_DEFAULT ""
fragment "$U" "exit 3" U_BOOT_DEFAULT ""
fragment "$U" "echo l2" U_BOOT_DEFAULT l2
# A value the user set is kept.
printf '#!/bin/sh\necho 6.12.1-ilp32-arm64\n' > "$W/sel/select"
chmod +x "$W/sel/select"
sed "s,/usr/lib/ilp32-kernel/select,$W/sel/select,g" "$ROOT/$G" > "$W/frag"
got=$(dash -e -c 'GRUB_TOP_LEVEL=mine; . "$0"; echo "$GRUB_TOP_LEVEL"' "$W/frag")
[ "$got" = mine ] && ok "user GRUB_TOP_LEVEL kept" || bad "user GRUB_TOP_LEVEL: $got"
sed "s,/usr/lib/ilp32-kernel/select,$W/sel/select,g" "$ROOT/$U" > "$W/frag"
got=$(dash -e -c 'U_BOOT_DEFAULT=mine; . "$0"; echo "$U_BOOT_DEFAULT"' "$W/frag")
[ "$got" = mine ] && ok "user U_BOOT_DEFAULT kept" || bad "user U_BOOT_DEFAULT: $got"

# The hooks exit 0 whatever happens, with their helper absent.
for f in etc/kernel/postinst.d/zz-ilp32-kernel etc/kernel/postrm.d/zz-ilp32-kernel etc/initramfs/post-update.d/zz-ilp32-kernel; do
	sed 's,/usr/lib/ilp32-kernel/raspi-apply,/nonexistent/raspi-apply,g' "$ROOT/$f" > "$W/hook"
	if DEB_MAINT_PARAMS="'configure' ''" dash "$W/hook"; then ok "$f without its helper"; else bad "$f without its helper"; fi
done

[ "$fail" = 0 ] && echo "check-boot-default: all ok" || { echo "check-boot-default: FAILED"; exit 1; }
