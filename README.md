# debian-ilp32

AArch64 ILP32 packages for *Debian* 13 (trixie). Unofficial; not affiliated with Debian.

ILP32 programs run 64-bit Arm code with 32-bit `long` and pointers, so pointer-heavy programs use
less memory (CPython 3.14: 23–31% lower max RSS than LP64, see
[llvm-ilp32 benchmarks](https://github.com/ilp32-a64/llvm-ilp32/blob/main/docs/benchmarks.md)).
These packages add the ILP32 runtime libraries next to Debian's own 64-bit libraries, a compiler,
and a kernel with the ILP32 ABI. The libraries and the compiler are Debian 13's own glibc, gcc-14
and binutils (same versions, same Debian patches, Debian's build options), built for ILP32. The
system stays a normal Debian 13 arm64 installation; nothing in Debian is changed or replaced.

## Install

```
# 1. the repository (once)
wget https://github.com/ilp32-a64/debian-ilp32/releases/download/v2026.10.24/ilp32-a64-archive-keyring_2026.10.24_all.deb
sudo apt install ./ilp32-a64-archive-keyring_2026.10.24_all.deb
sudo apt update

# 2. a kernel with the ILP32 ABI (skip if your kernel already has it)
sudo apt install linux-image-ilp32-arm64

# 3. the ILP32 runtime libraries
sudo apt install ilp32-runtime

# 4. reboot into the new kernel
sudo reboot
uname -r        # 6.12.114-ilp32-arm64

# 5. optional: the compiler, to build ILP32 programs on the machine itself
sudo apt install gcc-aarch64-linux-gnu-ilp32 g++-aarch64-linux-gnu-ilp32
```

Updates: `sudo apt update && sudo apt upgrade`. New kernel versions come as new packages
(`linux-image-6.12.N-ilp32-arm64`); `linux-image-ilp32-arm64` follows them with `apt upgrade` or
`apt full-upgrade` (`apt-get upgrade` keeps them back).

### Upgrading from 2026.10.24

Release 2026.10.27 rebuilt the GCC runtime libraries and the compiler from Debian 13's `gcc-14`
14.2.0-19, so their versions are lower than the GCC 14.3 packages of 2026.10.24, and `apt upgrade`
keeps the old ones (and, with the compiler installed, glibc too, which the old `libc6-dev-ilp32`
holds at its version). Switch once (the pin lets apt take this repository's versions, also lower ones):

```
printf 'Package: *\nPin: release o=ILP32-A64\nPin-Priority: 1001\n' | sudo tee /etc/apt/preferences.d/ilp32-a64-once
sudo apt update && sudo apt upgrade --allow-downgrades
sudo rm /etc/apt/preferences.d/ilp32-a64-once
```

Later updates need nothing special.

### Which machines

| Machine | Kernel | Status |
|---|---|---|
| UEFI with GRUB (servers, VMs, UEFI boards) | `linux-image-ilp32-arm64` | tested in QEMU |
| Raspberry Pi 3 Model B+ with Debian's [Raspberry Pi image](https://raspi.debian.net/) (`raspi-firmware`) | `linux-image-ilp32-arm64` | tested on hardware |
| Raspberry Pi 4 with Debian's [Raspberry Pi image](https://raspi.debian.net/) (`raspi-firmware`) | `linux-image-ilp32-arm64` | should work, untested |
| U-Boot boards with Debian's `u-boot-menu` (extlinux), e.g. the Marvell CN9130 CRB | `linux-image-ilp32-arm64` | tested on hardware (CN9130 CRB) |
| Boards that need a vendor kernel | the vendor kernel with the [ILP32 patches](https://github.com/ilp32-a64/linux-ilp32) | install `ilp32-runtime` only |

### About the kernel

- It is [linux-ilp32](https://github.com/ilp32-a64/linux-ilp32) `ilp32-6.12.y` (6.12.114: commit `64b6f40074`; 6.12 LTS, the same
  series as Debian 13), built with Debian 13's configuration (6.12.113) and compiler, plus the
  ILP32 ABI and Debian's `perf_event_paranoid` restriction. Drivers, firmware use and system
  settings stay as with Debian's kernel; 32-bit Arm (AArch32) programs keep running. The few
  configuration differences from Debian's are listed in [kernel/README.md](kernel/README.md).
- Security fixes for the kernel come from this repository, not from Debian.
- Secure Boot: the kernel is not signed; turn Secure Boot off.
- DKMS modules (NVIDIA, ZFS, …): install `linux-headers-ilp32-arm64`; it brings in `gcc-14` and
  `make`, and DKMS rebuilds the modules for the new kernel.
- Back to Debian's kernel: Debian's kernel stays installed; choose it under *Advanced options* in
  the GRUB menu, or remove ours with
  `sudo apt remove linux-image-ilp32-arm64 linux-image-6.12.114-ilp32-arm64`.

## Packages

All are `Architecture: arm64`, except the keyring (`all`):

| Package | Version | Content |
|---|---|---|
| `ilp32-runtime` | 2026.10.27 | metapackage: the five runtime libraries below and the keyring |
| `libc6-ilp32` | 2.41-12+deb13u4+ilp32a64.1 | Debian's glibc 2.41 with the ILP32 port ([glibc-ilp32](https://github.com/ilp32-a64/glibc-ilp32)) |
| `libgcc-s1-ilp32`, `libstdc++6-ilp32`, `libatomic1-ilp32`, `libgomp1-ilp32` | 14.2.0-19+ilp32a64.1 | runtime libraries of Debian's `gcc-14` |
| `linux-image-ilp32-arm64`, `linux-headers-ilp32-arm64` | 6.12.114+ilp32a64.2 | metapackages: the latest kernel and headers |
| `linux-image-6.12.114-ilp32-arm64`, `linux-headers-6.12.114-ilp32-arm64` | 6.12.114-1+ilp32a64.2 | the kernel and its headers |
| `ilp32-a64-archive-keyring` | 2026.10.24 | the repository key and apt source |
| `gcc-aarch64-linux-gnu-ilp32`, `g++-aarch64-linux-gnu-ilp32` | 14.2.0-19+ilp32a64.1 | metapackages: the compiler commands without version suffix |
| `gcc-14-aarch64-linux-gnu-ilp32`, `g++-14-aarch64-linux-gnu-ilp32` | 14.2.0-19+ilp32a64.1 | Debian's `gcc-14` C and C++ compilers for ILP32, running on arm64 |
| `binutils-aarch64-linux-gnu-ilp32` | 2.44-3+ilp32a64.1 | Debian's binutils for ILP32: assembler, linker and binary tools |
| `libc6-dev-ilp32` | 2.41-12+deb13u4+ilp32a64.1 | glibc headers, crt files, static libraries and linker scripts |
| `linux-libc-dev-ilp32` | 6.12.114-1+ilp32a64.2 | Linux UAPI headers with the ILP32 ABI |

Dynamic linker `/usr/lib/ld-linux-aarch64_ilp32.so.1`, libraries in `/usr/libilp32` (with a
`/libilp32` link). The repository is signed with the ILP32-A64 Archive Signing Key,
`D572 3B34 0CBE 7C99 2091 8243 9C6A 5E84 1E28 9B20`.

## Building ILP32 programs

On the machine itself, with the compiler packages (step 5 above):

```
aarch64-linux-gnu_ilp32-gcc -O2 -o hello hello.c       # C
aarch64-linux-gnu_ilp32-g++ -O2 -o app app.cc          # C++
aarch64-linux-gnu_ilp32-gcc -O2 -fopenmp -o omp omp.c  # OpenMP
./hello
```

The commands are named `aarch64-linux-gnu_ilp32-*` and live next to Debian's own `gcc` and
binutils without touching them. ILP32 headers are in `/usr/aarch64-linux-gnu_ilp32/include`, the
libraries in `/usr/libilp32`, the compiler's own files in `/usr/lib/gcc-cross/aarch64-linux-gnu_ilp32/14`
as with Debian's cross compilers; programs are PIE and get a build-id, as with Debian's compiler.
`-static` works too. Like Debian's gcc, it links with `--as-needed`: put libraries after the sources.

- The compiler is Debian 13's `gcc-14` 14.2.0-19 (the same version and patches as Debian's own
  `gcc`), plus two ILP32 fixes in libgcc (pointer authentication in the unwinder, ELF32 property
  notes). glibc and binutils are Debian 13's as well; how they are built is described below.
- GCC has no return address signing for ILP32: `-mbranch-protection=standard` and `pac-ret` stop
  with an error. Use `-mbranch-protection=bti`, or clang with the
  [llvm-ilp32](https://github.com/ilp32-a64/llvm-ilp32) patches, which supports `pac-ret` for ILP32.
  Debian's `dpkg-buildflags` adds `-mbranch-protection=standard` on arm64, so override it when
  building Debian packages for ILP32.

To cross-compile on another machine, use the toolchain from
[test-ilp32](https://github.com/ilp32-a64/test-ilp32) and copy the programs over; they find the
runtime libraries by themselves.

## How the packages are built

- Sources: Debian 13's `glibc` 2.41-12+deb13u4, `gcc-14` 14.2.0-19 and `binutils` 2.44-3 (the
  `.dsc` files, checked by sha256), with all of Debian's patches; the ILP32 patches on top are those
  of [glibc-ilp32](https://github.com/ilp32-a64/glibc-ilp32) and two libgcc fixes. Kernel UAPI
  headers from linux-ilp32 `64b6f40074`.
- Options: Debian's configure options and flags, with the changes ILP32 needs: the
  `aarch64-linux-gnu_ilp32` target, libraries in `/usr/libilp32`, `-mbranch-protection=bti` instead
  of `standard` (GCC has no `pac-ret` for ILP32), no memory tagging and no libmvec in glibc, no
  sanitizers, C and C++ only.
- glibc and GCC's target libraries are cross-built on x86-64; binutils and the compiler that runs on
  arm64 are built natively on an arm64 board. The build scripts are in
  [test-ilp32](https://github.com/ilp32-a64/test-ilp32) (`glibc/toolchain/`); they write install
  trees, which the scripts here turn into packages.
- Each package's `changelog.Debian.gz` starts with our entry, followed by the Debian entry of the
  version it is built from; `copyright` is Debian's.

## Build and test

```
runtime/build-debs.sh          # the runtime packages, from the install trees of glibc and gcc-14
keyring/build-keyring-deb.sh   # the keyring package
meta/build-meta-debs.sh        # the metapackages
toolchain/build-toolchain-debs.sh  # the dev and compiler packages, from the install trees
kernel/build-deb.sh            # the kernel packages, in a Debian 13 chroot (see kernel/README.md)
repo/make-repo.sh              # the apt repository (signed with repo/sign-release.sh)
tests/run-install-test.sh      # install, run, purge and reinstall in QEMU
tests/run-apt-test.sh          # apt with a signed repository, and rejection of bad signatures
tests/run-kernel-test.sh       # install the kernel package and boot it through UEFI and GRUB
tests/run-extmod-test.sh       # build and load an external module with the headers package
tests/run-upgrade-test.sh      # upgrade from the previous release, then to a new kernel version
tests/run-toolchain-test.sh    # build and run C, C++, OpenMP, static and shared programs on the guest
tests/scan-leaks.sh            # no build paths or host names in the packages
```

Needs sudo, `qemu-system-aarch64`, an ILP32 kernel image and network access to a Debian mirror.

## Why not multiarch?

dpkg still accepts an `arm64ilp32` architecture, but Multi-Arch packages must have exactly the same
version for every architecture: every glibc or GCC update in Debian would need a matching rebuild on
the same day. Separate ILP32 packages do not depend on Debian's versions and change nothing in Debian.

## License

The scripts are under the MIT license (see `LICENSE`); `kernel/config-debian` and `kernel/patches/` come
from Debian's `linux` package (GPL-2.0). The packages keep the licenses of glibc
(LGPL-2.1-or-later), GCC (GPL-3.0-or-later; the runtime libraries with the GCC Runtime Library
Exception), binutils (GPL-3.0-or-later) and Linux (GPL-2.0).
