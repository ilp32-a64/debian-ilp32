# kernel

Builds the kernel packages `linux-image-<version>-ilp32-arm64` and `linux-headers-<version>-ilp32-arm64`:
the [linux-ilp32](https://github.com/ilp32-a64/linux-ilp32) branch `ilp32-6.12.y` (6.12 stable with the
AArch64 ILP32 ABI) with Debian 13's arm64 kernel configuration, compiler and packaging conventions.

```
kernel/setup-chroot.sh                                  # once: Debian 13 build chroot (sudo, debootstrap)
kernel/chroot-run.sh env JOBS=2 "$PWD/kernel/build-deb.sh"
```

Inputs:

- `KERNEL_SRC`: a work tree of `linux-ilp32` `ilp32-6.12.y`, `REV` the commit (default `HEAD`);
  6.12.114-1+ilp32a64.1 is `64b6f40074`
- `config-debian`: the arm64 kernel configuration of `linux-image-6.12.113+deb13-arm64-unsigned`
  (Debian, GPL-2); `build-deb.sh` adds ILP32 (`ARM64_ILP32`, `COMPAT_32BIT_TIME`) and builds binder in
- `patches/`: Debian's patch for `kernel.perf_event_paranoid=3` (`SECURITY_PERF_EVENTS_RESTRICT`), from
  the Debian `linux` package (GPL-2), refreshed for 6.12.114

Built with Debian 13's cross toolchain in the chroot (gcc-14, binutils 2.44, pahole for BTF), an
uncompressed `Image`, the AArch32 compat vDSO, Debian's debug info and BTF settings. `fix-headers-deb.sh`
removes build-host files from `linux-headers`, makes the kernel's compiler its default and adds
`Depends: gcc-14, make, libc6-dev`.

Outputs in `OUT` (default `~/work/debian-ilp32-kernel/out`): the `linux-image` and `linux-headers` .debs.
`linux-libc-dev` and the `-dbg` package (`OUT/dbg/`, about 1 GB) are built too but not published.
See the header of each script for its environment variables.
