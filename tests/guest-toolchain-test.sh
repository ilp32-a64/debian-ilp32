#!/bin/bash
# SPDX-License-Identifier: MIT
# Toolchain test inside Debian 13 arm64 on the ILP32 kernel (see run-toolchain-test.sh): install
# the runtime and compiler packages, then build ILP32 programs on the machine itself and run them.
T=aarch64-linux-gnu_ilp32
S=/ilp32-test/src
B=/root/build
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }
# expect <what> <pattern> <command...>: the command output must match the pattern
expect() {
	local what=$1 pat=$2 out
	shift 2
	out=$("$@" 2>&1)
	if echo "$out" | grep -qE "$pat"; then echo "RESULT ok: $what"; else echo "RESULT FAIL: $what"; echo "$out" | head -5; fi
}

step "C1 install"
check dpkg -i /ilp32-test/debs/*.deb
dpkg -l "*-ilp32" "*ilp32*" | grep '^ii' | awk '{print $2, $3}'
$T-gcc --version | head -1
$T-ld --version | head -1
mkdir -p $B && cd $B

step "C2 C, dynamic"
check $T-gcc -O2 -Wall -o hello $S/hello.c
check ./hello
expect "interpreter /lib/ld-linux-aarch64_ilp32.so.1" 'interpreter: /lib/ld-linux-aarch64_ilp32.so.1' $T-readelf -l hello
expect "ELF32 AArch64" 'Class: +ELF32' $T-readelf -h hello
expect "needs libc.so.6" '^ 0x[0-9a-f]+ \(NEEDED\) +Shared library: \[libc.so.6\]$' $T-readelf -d hello
expect "PIE by default" 'Type: +DYN' $T-readelf -h hello

step "C3 C++ (libstdc++, exceptions through libgcc_s)"
check $T-g++ -O2 -Wall -o hello++ $S/hello++.cc
check ./hello++
cat > exc.cc <<'EOF'
#include <stdexcept>
#include <cstdio>
static void f(int n) { if (n == 0) throw std::runtime_error("deep"); f(n - 1); }
int main() { try { f(50); } catch (const std::exception &e) { std::printf("caught %s\n", e.what()); return 0; } return 1; }
EOF
check $T-g++ -O2 -o exc exc.cc
check ./exc

step "C4 OpenMP, libm, libatomic, iconv, NSS"
check $T-gcc -O2 -fopenmp -o runtime-test $S/runtime-test.c -lm -latomic
check ./runtime-test

step "C5 static"
check $T-gcc -O2 -static -o hello-static $S/hello.c
check ./hello-static
check sh -c "! $T-readelf -l hello-static | grep -q INTERP"
check $T-g++ -O2 -static -o exc-static exc.cc
check ./exc-static

step "C6 shared library"
cat > lib.c <<'EOF'
int add(int a, int b) { return a + b; }
EOF
cat > main.c <<'EOF'
#include <stdio.h>
int add(int, int);
int main(void) { printf("add = %d, sizeof(long) = %zu\n", add(2, 3), sizeof(long)); return add(2, 3) != 5; }
EOF
check $T-gcc -O2 -shared -fPIC -o libadd.so lib.c
check $T-gcc -O2 -o main main.c -L. -ladd
check env LD_LIBRARY_PATH=. ./main

step "C7 LTO and the binutils"
check $T-gcc -O2 -flto -o hello-lto $S/hello.c
check ./hello-lto
check $T-objdump -h hello > /dev/null
check $T-gcc-ar --version > /dev/null

step "C8 search paths"
$T-gcc -print-search-dirs | sed 's/^/INFO /' | cut -c1-200
echo | $T-gcc -E -Wp,-v - 2>&1 | sed -n '/#include <...>/,/End of/p' | sed 's/^/INFO /'

step "C9 defaults"
inc=$(echo | $T-gcc -E -Wp,-v - 2>&1 | sed -n "/#include <...>/,/End of/p")
if echo "$inc" | grep -qx " /usr/local/include"; then
	echo "RESULT FAIL: /usr/local/include (LP64 headers) is in the ILP32 include search list"
else
	echo "RESULT ok: no /usr/local/include in the include search list"
fi
expect "build-id note" "Build ID" $T-readelf -n hello
expect "GNU hash" "GNU_HASH" $T-readelf -d hello
