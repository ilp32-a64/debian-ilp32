# Default boot kernel

`linux-image-ilp32-arm64` keeps the newest ILP32 kernel as the default boot entry. Debian's kernel
stays installed, but once its version is higher than ours the normal rule would boot it, and ILP32
programs do not run there. `root/` and `DEBIAN/` here are added to that package.

Only the metapackage carries this, because versioned kernel packages can be installed side by side
and could not own the same files. A system with only a versioned kernel package has none of this.

`/usr/lib/ilp32-kernel/select` makes the choice: the newest `*-ilp32-arm64` kernel with an initrd.

| Boot method | Mechanism | Runs when |
|---|---|---|
| GRUB | `/etc/default/grub.d/ilp32-kernel.cfg` sets `GRUB_TOP_LEVEL` | every `update-grub` |
| extlinux | `/usr/share/u-boot-menu/conf.d/ilp32-kernel.conf` sets `U_BOOT_DEFAULT` | every `u-boot-update` |
| Raspberry Pi | `zz-ilp32-kernel` hooks and a trigger call `raspi-apply` after `z50-raspi-firmware` | every run of z50 |

GRUB and extlinux need no hook: Debian's kernel hooks run those tools, and the fragments choose
again each time. No state is kept, so a removed kernel or package cannot leave a stale setting.
A `GRUB_DEFAULT` that is not 0, a `GRUB_TOP_LEVEL` or a `U_BOOT_DEFAULT` set by the user is kept.

Raspberry Pi: `raspi-apply` keeps the newest other kernel on the firmware partition, copies the
ILP32 kernel, initrd and device trees there, and then changes the `kernel=` and `initramfs` lines of
the `config.txt` that z50 generated. If something fails, z50's result stays. To recover a Pi that
does not boot, edit those two lines on the firmware partition from another computer, naming the
`vmlinuz-*` and `initrd.img-*` of the other kernel. It is not touched on other boot methods.

Off switch: `ILP32_KERNEL_DEFAULT=no` in `/etc/default/ilp32-kernel`, then
`ilp32-kernel-update-boot`. The result is the same `grub.cfg`, `extlinux.conf`, `config.txt` and
`cmdline.txt` as without this package; kernels already on a Pi's firmware partition stay until
their packages are removed.

Removal: `apt remove` regenerates the boot configuration by the system's normal rule and leaves the
conffiles, which do nothing without `/usr/lib/ilp32-kernel`; `apt purge` removes them too.

With this on, the system does not boot Debian's kernel updates, including security updates, until a
newer ILP32 kernel package follows them.

Other boot methods (flash-kernel, systemd-boot, kernel-install) are not handled.

Tests: `tests/check-boot-default.sh` (no VM), `tests/run-boot-default-test.sh` (QEMU).
