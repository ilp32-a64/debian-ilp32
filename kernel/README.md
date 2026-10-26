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
  6.12.114-1+ilp32a64.1 and +ilp32a64.2 are `64b6f40074`
- `config-debian`: the arm64 kernel configuration of `linux-image-6.12.113+deb13-arm64-unsigned`
  (Debian, GPL-2); `build-deb.sh` adds ILP32 (`ARM64_ILP32`, `COMPAT_32BIT_TIME`) and builds binder in
- `patches/`: Debian's patch for `kernel.perf_event_paranoid=3` (`SECURITY_PERF_EVENTS_RESTRICT`), from
  the Debian `linux` package (GPL-2), refreshed for 6.12.114

Differences of the packaged `/boot/config` from Debian's (`scripts/diffconfig`, 11 lines):

| Options | Why |
|---|---|
| `+ARM64_ILP32 y`, `+AARCH32_EL0 y`, `+COMPAT_TASK_SIZE n`, `-COMPAT_BINFMT_ELF y` | the ILP32 series (`AARCH32_EL0` is its split of `COMPAT`; arm64 has its own AArch32 and ILP32 ELF loaders) |
| `ANDROID_BINDER_IPC m -> y` | built in: a module only with Debian's binder patches |
| `PINCTRL_MCP23S08 n -> m`, `+PINCTRL_MCP23S08_I2C m`, `+PINCTRL_MCP23S08_SPI m` | the MCP23017 GPIO expander of the CN9130 CRB board (USB-A, eMMC, SFP regulators) |
| `-LOCK_DOWN_IN_EFI_SECURE_BOOT y` | a Debian patch; no Secure Boot |
| `+FB_NVIDIA n`, `+FB_RIVA n` | Debian removes these drivers (DFSG); off here |

Built with Debian 13's cross toolchain in the chroot (gcc-14, binutils 2.44, pahole for BTF), an
uncompressed `Image`, the AArch32 compat vDSO, Debian's debug info and BTF settings. `fix-headers-deb.sh`
removes build-host files from `linux-headers`, makes the kernel's compiler its default and adds
`Depends: gcc-14, make, libc6-dev`.

Outputs in `OUT` (default `~/work/debian-ilp32-kernel/out`): the `linux-image` and `linux-headers` .debs.
`linux-libc-dev` and the `-dbg` package (`OUT/dbg/`, about 1 GB) are built too but not published.
See the header of each script for its environment variables.
