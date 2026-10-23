#!/bin/bash
# SPDX-License-Identifier: MIT
# PID 1 of the QEMU test guest: run /ilp32-test/test.sh, then power off.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev 2>/dev/null
mkdir -p /dev/pts && mount -t devpts devpts /dev/pts
mount -o remount,rw /
cd /ilp32-test
/bin/bash ./test.sh 2>&1
echo "ILP32-TEST-END"
# debootstrap's second stage unmounts /proc; mount it again for sysrq.
mount -t proc proc /proc 2>/dev/null
sync
# Leave the root file system clean for the next boot of the image.
mount -o remount,ro / 2>/dev/null || true
echo o > /proc/sysrq-trigger
# Wait without starting a program from the disk, which is going away.
read -r -t 30 < /dev/console || true
