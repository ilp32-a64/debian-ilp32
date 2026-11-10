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
wget https://github.com/ilp32-a64/debian-ilp32/releases/download/v2026.11.04/ilp32-a64-archive-keyring_2026.10.24_all.deb
sudo apt install ./ilp32-a64-archive-keyring_2026.10.24_all.deb
sudo apt update

# 2. a kernel with the ILP32 ABI (skip if your kernel already has it)
sudo apt install linux-image-ilp32-arm64

# 3. the ILP32 runtime libraries
sudo apt install ilp32-runtime

# 4. reboot into the new kernel
sudo reboot
uname -r        # 6.12.115-ilp32-arm64

# 5. optional: the compiler, to build ILP32 programs on the machine itself
sudo apt install gcc-aarch64-linux-gnu-ilp32 g++-aarch64-linux-gnu-ilp32

# 6. optional: Python 3.13 for ILP32 (python3-ilp32), and its headers for C extensions
sudo apt install python3-ilp32 python3.13-dev-ilp32
```

Updates: `sudo apt update && sudo apt upgrade`. New kernel versions come as new packages
(`linux-image-6.12.N-ilp32-arm64`); `linux-image-ilp32-arm64` follows them with `apt upgrade` or
`apt full-upgrade` (`apt-get upgrade` keeps them back).

2026.11.04 changed the C++ and OpenMP runtime ABI (libstdc++ and libgomp use futexes now, see
below): rebuild ILP32 programs built with an earlier compiler if they use `std::future`,
`std::promise`, `std::async`, `std::shared_future`, `atomic::wait`/`notify`, or OpenMP locks.
C programs and other C++ programs are not affected.

### Which machines

| Machine | Kernel | Status |
|---|---|---|
| UEFI with GRUB (servers, VMs, UEFI boards) | `linux-image-ilp32-arm64` | tested in QEMU |
| Raspberry Pi 3 Model B+ with Debian's [Raspberry Pi image](https://raspi.debian.net/) (`raspi-firmware`) | `linux-image-ilp32-arm64` | tested on hardware (6.12.115, including the default boot entry) |
| Raspberry Pi 4 with Debian's [Raspberry Pi image](https://raspi.debian.net/) (`raspi-firmware`) | `linux-image-ilp32-arm64` | should work, untested |
| U-Boot boards with Debian's `u-boot-menu` (extlinux), e.g. the Marvell CN9130 CRB or the Globalscale ESPRESSObin | `linux-image-ilp32-arm64` | tested on hardware (CN9130 CRB with 6.12.114; ESPRESSObin v5, 1 GiB, with 6.12.115, including the default boot entry) |
| Boards that need a vendor kernel | the vendor kernel with the [ILP32 patches](https://github.com/ilp32-a64/linux-ilp32) | install `ilp32-runtime` only |

Raspberry Pi: Debian 13's images are linked on the front page of [raspi.debian.net](https://raspi.debian.net/)
(`debian-13-raspi-arm64` from cloud.debian.org). They grow the root file system but not its
partition, which stays at about 2.5 GB, and they have no SSH server. Before installing the packages
above, grow the root partition to the card (for example with `growpart` from `cloud-guest-utils`,
then `resize2fs`) and install `openssh-server` from the console if you want remote access.

### About the kernel

- It is [linux-ilp32](https://github.com/ilp32-a64/linux-ilp32) `ilp32-6.12.y` (6.12.115: commit `0f465af64b`; 6.12 LTS, the same
  series as Debian 13), built with Debian 13's configuration (6.12.113, the same as 6.12.115's) and compiler, plus the
  ILP32 ABI and Debian's `perf_event_paranoid` restriction. Drivers, firmware use and system
  settings stay as with Debian's kernel; 32-bit Arm (AArch32) programs keep running. The few
  configuration differences from Debian's are listed in [kernel/README.md](kernel/README.md).
- Security fixes for the kernel come from this repository, not from Debian.
- **Default boot entry.** Boot loaders normally boot the kernel with the highest version, so a newer
  Debian kernel (for example from `trixie-security`, also installed by `unattended-upgrades`) would
  be booted, and ILP32 programs would then fail with `exec format error`. `linux-image-ilp32-arm64`
  keeps the newest ILP32 kernel as the default instead: for GRUB (`/etc/default/grub.d/ilp32-kernel.cfg`),
  for extlinux via `u-boot-menu`, and for the Raspberry Pi's `config.txt` (after `raspi-firmware`).
  Debian's kernel stays installed and in the boot menu. To turn this off, set
  `ILP32_KERNEL_DEFAULT=no` in `/etc/default/ilp32-kernel` and run `sudo ilp32-kernel-update-boot`.
  With it on, the machine does not boot Debian's kernel updates, including security updates, until
  a newer ILP32 kernel package follows them. Details: [meta/boot-default/README.md](meta/boot-default/README.md).
  `unattended-upgrades` installs only Debian's packages, so updates from this repository need
  `sudo apt upgrade`.
- **ESPRESSObin (Armada 3720) SD cards at SDR104.** With the default tuning step, SD reads at SDR104
  sometimes put wrong data in the page cache (the card's data stays correct; nothing is logged), on
  two cards from different makers, also with Debian's own kernels. Our kernel's ESPRESSObin device
  trees set `marvell,xenon-phy-tun-step-divider = <128>`, which was clean in 56 of 56 reboots at the
  same speed (Debian's kernels and our 6.12.114 do not have it). Tested on one ESPRESSObin v5 only.
- **seccomp.** From 6.12.115-1+ilp32a64.3, ILP32 programs report their own audit architecture,
  `AUDIT_ARCH_AARCH64ILP32` (`0xd00000b7`); earlier kernels reported `AUDIT_ARCH_AARCH64`, so a filter
  written for 64-bit Arm could be bypassed by an ILP32 program through its time64 system calls.
  Debian's systemd and libseccomp do not know the new architecture: in a unit with
  `SystemCallArchitectures=native`, ILP32 programs are refused (`SIGSYS`; remove that line to run one),
  and `SystemCallFilter=` alone does not apply to them, as for any architecture systemd does not know.
- Secure Boot: the kernel is not signed; turn Secure Boot off.
- DKMS modules (NVIDIA, ZFS, …): install `linux-headers-ilp32-arm64`; it brings in `gcc-14` and
  `make`, and DKMS rebuilds the modules for the new kernel.
- Back to Debian's kernel: Debian's kernel stays installed; choose it in the GRUB (*Advanced options*)
  or extlinux menu, turn the default off as above, or remove ours with
  `sudo apt remove linux-image-ilp32-arm64 linux-image-6.12.115-ilp32-arm64` (and older ones).

## Packages

All are `Architecture: arm64`, except the keyring (`all`):

| Package | Version | Content |
|---|---|---|
| `ilp32-runtime` | 2026.10.27 | metapackage: the five runtime libraries below and the keyring |
| `libc6-ilp32` | 2.41-12+deb13u4+ilp32a64.2 | Debian's glibc 2.41 with the ILP32 port ([glibc-ilp32](https://github.com/ilp32-a64/glibc-ilp32)) |
| `libstdc++6-ilp32`, `libgomp1-ilp32` | 14.2.0-19+ilp32a64.2 | runtime libraries of Debian's `gcc-14` (with futexes) |
| `libgcc-s1-ilp32`, `libatomic1-ilp32` | 14.2.0-19+ilp32a64.1 | runtime libraries of Debian's `gcc-14` |
| `linux-image-ilp32-arm64`, `linux-headers-ilp32-arm64` | 6.12.115+ilp32a64.3 | metapackages: the latest kernel and headers (the image one also keeps it the default boot entry) |
| `linux-image-6.12.115-ilp32-arm64`, `linux-headers-6.12.115-ilp32-arm64` | 6.12.115-1+ilp32a64.3 | the kernel and its headers |
| `ilp32-a64-archive-keyring` | 2026.10.24 | the repository key and apt source |
| `gcc-aarch64-linux-gnu-ilp32`, `g++-aarch64-linux-gnu-ilp32` | 14.2.0-19+ilp32a64.4 | metapackages: the compiler commands without version suffix |
| `gcc-14-aarch64-linux-gnu-ilp32`, `g++-14-aarch64-linux-gnu-ilp32` | 14.2.0-19+ilp32a64.4 | Debian's `gcc-14` C and C++ compilers for ILP32, running on arm64 |
| `binutils-aarch64-linux-gnu-ilp32` | 2.44-3+ilp32a64.1 | Debian's binutils for ILP32: assembler, linker and binary tools |
| `libc6-dev-ilp32` | 2.41-12+deb13u4+ilp32a64.2 | glibc headers, crt files, static libraries and linker scripts |
| `linux-libc-dev-ilp32` | 6.12.114-1+ilp32a64.2 | Linux UAPI headers with the ILP32 ABI |
| `python3-ilp32` | 3.13.5-2+deb13u5+ilp32a64.1 | metapackage: the `python3-ilp32` command |
| `python3.13-ilp32`, `libpython3.13-ilp32`, `python3.13-dev-ilp32` | 3.13.5-2+deb13u5+ilp32a64.1 | Debian's Python 3.13 for ILP32: interpreter and standard library, shared library, headers |

Libraries for Python and for building ILP32 programs, each as `<Debian's name>-ilp32` and
`<Debian's -dev name>-ilp32` (e.g. `libssl3t64-ilp32`, `libssl-dev-ilp32`), from Debian 13's sources:

| Source | Version | Packages |
|---|---|---|
| zlib | 1:1.3.dfsg+really1.3.1-1+ilp32a64.1 | `zlib1g-ilp32`, `zlib1g-dev-ilp32` |
| bzip2 | 1.0.8-6+ilp32a64.1 | `libbz2-1.0-ilp32`, `libbz2-dev-ilp32` |
| xz-utils | 5.8.1-1+deb13u2+ilp32a64.1 | `liblzma5-ilp32`, `liblzma-dev-ilp32` |
| libzstd | 1.5.7+dfsg-1+ilp32a64.1 | `libzstd1-ilp32`, `libzstd-dev-ilp32` |
| libffi | 3.4.8-2+ilp32a64.1 | `libffi8-ilp32`, `libffi-dev-ilp32` |
| expat | 2.9.0-1~deb13u1+ilp32a64.1 | `libexpat1-ilp32`, `libexpat1-dev-ilp32` |
| ncurses | 6.5+20250216-2+ilp32a64.1 | `libtinfo6-ilp32`, `libncurses6-ilp32`, `libncursesw6-ilp32`, `libncurses-dev-ilp32` |
| readline | 8.2-6+ilp32a64.1 | `libreadline8t64-ilp32`, `libreadline-dev-ilp32` |
| sqlite3 | 3.46.1-7+deb13u2+ilp32a64.1 | `libsqlite3-0-ilp32`, `libsqlite3-dev-ilp32` |
| openssl | 3.5.7-1~deb13u3+ilp32a64.1 | `libssl3t64-ilp32`, `openssl-provider-legacy-ilp32`, `libssl-dev-ilp32` |
| util-linux | 2.41.5-0+deb13u1+ilp32a64.1 | `libuuid1-ilp32`, `uuid-dev-ilp32` |

Only the libraries are packaged, not the programs (no `openssl`, `sqlite3` or `xz` commands for
ILP32); Debian's own programs keep working as before.

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
  `gcc`), plus ILP32 fixes in libgcc and libatomic (pointer authentication in the unwinder, ELF32
  property notes). glibc and binutils are Debian 13's as well; how they are built is described below.
- GCC has no return address signing for ILP32: `-mbranch-protection=standard` and `pac-ret` stop
  with an error. Use `-mbranch-protection=bti`, or clang with the
  [llvm-ilp32](https://github.com/ilp32-a64/llvm-ilp32) patches, which supports `pac-ret` for ILP32.
  Debian's `dpkg-buildflags` adds `-mbranch-protection=standard` on arm64, so override it when
  building Debian packages for ILP32.

To cross-compile on another machine, use the toolchain from
[test-ilp32](https://github.com/ilp32-a64/test-ilp32) and copy the programs over; they find the
runtime libraries by themselves.

## Python

`python3-ilp32` (Debian's Python 3.13 built for ILP32) installs next to Debian's own `python3`
and shares nothing with it but `/usr/local/bin` for scripts that pip installs:

- Commands: `python3-ilp32`, `python3.13-ilp32`, `python3.13-ilp32-config`, `pydoc3.13-ilp32`,
  `pdb3.13-ilp32`. The standard library is in `/usr/libilp32/python3.13`.
- Its own module directories: `/usr/libilp32/python3/dist-packages` (packages),
  `/usr/local/libilp32/python3.13/dist-packages` (pip as root),
  `~/.local/libilp32/python3.13/site-packages` (pip `--user`). Debian's `/usr/lib/python3/dist-packages`
  is not on its path: Debian's Python modules with C code are LP64 and cannot load.
- Wheels: the platform is `linux-aarch64_ilp32` and pip accepts only `linux_aarch64_ilp32` and
  pure-Python (`any`) wheels; it refuses `linux_armv7l` and `manylinux_*_aarch64` wheels, which
  are not ILP32. Packages with C extensions build from source with `python3.13-dev-ilp32` and the
  compiler (step 6).
- `python3-ilp32 -m venv` works (with Debian's `python3-pip-whl`); in a venv `libilp32` is a link
  to `lib`, as `lib64` is on 64-bit systems.
- `ctypes.util.find_library()` returns only ILP32 libraries, from `LD_LIBRARY_PATH`, the cache and
  `/usr/libilp32`.
- OpenSSL's legacy algorithms (MD4, RIPEMD-160) need the legacy provider activated in the OpenSSL
  configuration, as with Debian's own Python.

Tested with Python's test suite at build time (failures: `test_ctypes`, which calls the LP64 `gcc`
and passes with the ILP32 one, and `test_freeze` in the shared build, which fails the same way in
Debian's own arm64 build) and with `tests/run-python-test.sh`, in QEMU and on an ESPRESSObin v5
(1 GiB).

## How the packages are built

- Sources: Debian 13's `glibc` 2.41-12+deb13u4, `gcc-14` 14.2.0-19, `binutils` 2.44-3 and the
  sources in the tables above (the
  `.dsc` files, checked by sha256), with all of Debian's patches; the ILP32 patches on top are those
  of [glibc-ilp32](https://github.com/ilp32-a64/glibc-ilp32) and the libgcc/libatomic fixes (the
  compiler's full source: [gcc-ilp32](https://github.com/ilp32-a64/gcc-ilp32) branch
  `ilp32-14.2.0-19`, on top of Debian's patches in `debian-14.2.0-19`). Kernel UAPI headers from
  linux-ilp32 `64b6f40074`.
- Options: Debian's configure options and flags, with the changes ILP32 needs: the
  `aarch64-linux-gnu_ilp32` target, libraries in `/usr/libilp32`, `-mbranch-protection=bti` instead
  of `standard` (GCC has no `pac-ret` for ILP32), no memory tagging and no libmvec in glibc, no
  sanitizers, C and C++ only. Debian's `libgomp-omp_h-multilib` patch is left out: it sizes the
  `omp.h` lock types for LP64 multilibs; ILP32 keeps the sizes libgomp's configure measures.
- Futexes: glibc for ILP32 has only `SYS_futex_time64`, so GCC's configure fell back to the slower
  POSIX code in libgomp, libitm and libstdc++, and libgomp could hang. Since 2026.11.04, `SYS_futex`
  is defined as `SYS_futex_time64` where only the latter exists (GCC PR 93421, PR 97182).
- glibc and GCC's runtime libraries are cross-built on x86-64; binutils and the compiler that runs
  on arm64 are built natively on an arm64 board, the compiler in a fresh Debian 13 chroot against
  the released ILP32 packages of this repository. The build scripts are in
  [test-ilp32](https://github.com/ilp32-a64/test-ilp32) (`glibc/toolchain/`); they write install
  trees, which the scripts here turn into packages.
- The libraries and Python are built the same way, natively in fresh Debian 13 chroots on arm64,
  with Debian's own options and patches plus small ILP32 patches (configure's `linux-gnu_ilp32`,
  ELF32 property notes in hand-written assembly of zstd, libffi and OpenSSL, and Python's platform
  tag, module paths, venv link and `find_library`); `libs/build-lib-debs.sh` packages them.
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
tests/run-python-test.sh       # Python: modules, libraries, C extensions, venv, pip's platform tags
libs/build-lib-debs.sh         # the library and Python packages, from install trees
tests/scan-leaks.sh            # no build paths or host names in the packages
```

Needs sudo, `qemu-system-aarch64`, an ILP32 kernel image and network access to a Debian mirror.

## Why not multiarch?

dpkg still accepts an `arm64ilp32` architecture, but Multi-Arch packages must have exactly the same
version for every architecture: every glibc or GCC update in Debian would need a matching rebuild on
the same day. Separate ILP32 packages do not depend on Debian's versions and change nothing in Debian.
Debian's earlier [arm64ilp32 port](https://wiki.debian.org/Arm64ilp32Port) (2016–2019) took the
multiarch route; some of its fixes are still in Debian's sources, e.g. OpenSSL's `debian-arm64ilp32`
target, which these packages use.

## License

The scripts are under the MIT license (see `LICENSE`); `kernel/config-debian` and `kernel/patches/` come
from Debian's `linux` package (GPL-2.0). The packages keep the licenses of glibc
(LGPL-2.1-or-later), GCC (GPL-3.0-or-later; the runtime libraries with the GCC Runtime Library
Exception), binutils (GPL-3.0-or-later), Linux (GPL-2.0), Python (PSF-2.0) and the libraries'
own licenses, as in each package's `copyright` file.
