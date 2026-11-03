#!/bin/bash
# SPDX-License-Identifier: MIT
# Python test inside Debian 13 arm64 on the ILP32 kernel (see run-python-test.sh): install the
# ILP32 runtime, compiler and CPython set with apt, then check the interpreter, its modules and
# libraries, a C extension built against python3.13-dev-ilp32, and pip's platform tags.
# Usage: guest-python-test.sh <Debian mirror>      (QEMU guest)
#        BOARD=1 DEBS=<dir> guest-python-test.sh    (a real Debian 13 arm64 board with an ILP32 kernel)
T=aarch64-linux-gnu_ilp32
PY=python3-ilp32
B=/root/pytest
step() { echo; echo "=== $*"; }
check() { "$@"; local r=$?; if [ $r = 0 ]; then echo "RESULT ok: $*"; else echo "RESULT FAIL($r): $*"; fi; }
# expect <what> <pattern> <command...>: the command output must match the pattern
expect() {
	local what=$1 pat=$2 out
	shift 2
	out=$("$@" 2>&1)
	if echo "$out" | grep -qE "$pat"; then echo "RESULT ok: $what"; else echo "RESULT FAIL: $what"; echo "$out" | tail -8; fi
}

step "P1 install with apt (Debian's python3-pip from ${1:-the system sources}, for the pip checks)"
# On a real board (BOARD=1) the network, /dev/shm and the apt sources are the system's own.
if [ -z "${BOARD:-}" ]; then
	ip link set lo up
	dev=$(ls /sys/class/net | grep -v lo | head -1)
	ip link set "$dev" up && ip addr add 10.0.2.15/24 dev "$dev" && ip route add default via 10.0.2.2
	echo "nameserver 10.0.2.3" > /etc/resolv.conf
	# POSIX semaphores (multiprocessing) need /dev/shm, which the test init does not mount
	mkdir -p /dev/shm && mount -t tmpfs tmpfs /dev/shm
	echo "deb $1 trixie main" > /etc/apt/sources.list
fi
DEBS=${DEBS:-/ilp32-test/debs}
check apt-get update -q
check apt-get install -y -q --no-install-recommends "$DEBS"/*.deb python3-pip python3-pip-whl python3-setuptools-whl
dpkg -l '*-ilp32' | grep '^ii' | awk '{print "INFO", $2, $3}'
mkdir -p $B && cd $B

step "P2 interpreter"
check $PY -c 'import sys; print(sys.version)'
expect "pointers are 32 bits" '^4$' $PY -c 'import struct; print(struct.calcsize("P"))'
expect "platform linux-aarch64_ilp32" '^linux-aarch64_ilp32$' $PY -c 'import sysconfig; print(sysconfig.get_platform())'
expect "extension suffix" 'cpython-313-aarch64_ilp32-linux-gnu\.so' $PY -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))'
expect "ILP32 site dirs only" '/usr/libilp32/python3/dist-packages' $PY -c 'import sys; print(sys.path)'
check sh -c "! $PY -c 'import sys; print(sys.path)' | grep -q /usr/lib/python3/dist-packages"
check test -d /usr/local/libilp32/python3.13/dist-packages
expect "stdlib byte-compiled" '[0-9]' sh -c 'find /usr/libilp32/python3.13 -name "*.pyc" | wc -l'

step "P3 modules and their libraries"
for m in ssl hashlib sqlite3 ctypes readline lzma bz2 zlib uuid decimal curses pyexpat _ctypes _ssl _sqlite3 \
	_lzma _bz2 _uuid _decimal _curses _hashlib json asyncio multiprocessing; do
	check $PY -c "import $m"
done
expect "openssl 3.5" 'OpenSSL 3\.5' $PY -c 'import ssl; print(ssl.OPENSSL_VERSION)'
# the legacy provider loads when a configuration activates it; whether Debian's default
# configuration does is printed below for both interpreters
cat > legacy.cnf <<'EOF'
openssl_conf = init
[init]
providers = prov
[prov]
default = act
legacy = act
[act]
activate = 1
EOF
expect "md4 from the legacy provider" '^31d6cfe0d16ae931b73c59d7e0c089c0$' env OPENSSL_CONF=$B/legacy.cnf $PY -c 'import hashlib; print(hashlib.new("md4", b"").hexdigest())'
echo "INFO md4 with the default configuration: ILP32 $($PY -c 'import hashlib; hashlib.new("md4")' >/dev/null 2>&1 && echo yes || echo no), Debian's python3 $(python3 -c 'import hashlib; hashlib.new("md4")' >/dev/null 2>&1 && echo yes || echo no)"
expect "sqlite 3.46" '^3\.46' $PY -c 'import sqlite3; print(sqlite3.sqlite_version)'
expect "ctypes calls libc" '^5$' $PY -c 'import ctypes; print(ctypes.CDLL(None).strlen(b"hello"))'
expect "lzma/bz2/zlib round trip" '^ok$' $PY -c '
import lzma, bz2, zlib
d = b"x" * 100000
assert lzma.decompress(lzma.compress(d)) == d and bz2.decompress(bz2.compress(d)) == d
assert zlib.decompress(zlib.compress(d)) == d
print("ok")'
expect "decimal (bundled libmpdec)" '^0\.1428571428571428571428571429$' $PY -c 'import decimal; print(decimal.Decimal(1) / decimal.Decimal(7))'
expect "threads and processes" '^ok$' $PY -c '
import concurrent.futures as f
with f.ProcessPoolExecutor(2) as p: assert sum(p.map(abs, range(-50, 50))) == 2500
with f.ThreadPoolExecutor(4) as t: assert sum(t.map(abs, range(-50, 50))) == 2500
print("ok")'
# every ILP32 shared object resolves its libraries in /usr/libilp32 only
for f in /usr/libilp32/*.so.* /usr/libilp32/python3.13/lib-dynload/*.so /usr/libilp32/ossl-modules/*.so /usr/bin/python3.13-ilp32; do
	[ -f "$f" ] || continue
	out=$(/usr/lib/ld-linux-aarch64_ilp32.so.1 --list "$f" 2>&1)
	if echo "$out" | grep -q 'not found' || echo "$out" | grep -E '=> /' | grep -vqE '=> /((usr/)?libilp32/|usr/lib/ld-linux-aarch64_ilp32\.so\.1 )'; then
		echo "RESULT FAIL: libraries of $f"; echo "$out" | head -5
	fi
done
echo "RESULT ok: library resolution checked"

step "P4 C extension with python3.13-dev-ilp32"
cat > spam.c <<'EOF'
#include <Python.h>
static PyObject *size(PyObject *self, PyObject *args) { return PyLong_FromLong(sizeof(void *)); }
static PyMethodDef m[] = { { "size", size, METH_NOARGS, 0 }, { 0 } };
static struct PyModuleDef d = { PyModuleDef_HEAD_INIT, "spam", 0, -1, m };
PyMODINIT_FUNC PyInit_spam(void) { return PyModule_Create(&d); }
EOF
ext=$($PY -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')
check $T-gcc -O2 -fPIC -shared $(python3.13-ilp32-config --includes) -o "spam$ext" spam.c
expect "extension imports" '^4$' $PY -c 'import spam; print(spam.size())'
check $T-gcc -O2 -o embed -x c - $(python3.13-ilp32-config --cflags --ldflags --embed) <<'EOF'
#include <Python.h>
int main(void) { Py_Initialize(); PyRun_SimpleString("import sys; print('embedded', sys.maxsize)"); return Py_FinalizeEx(); }
EOF
expect "embedded interpreter" '^embedded 2147483647$' ./embed

step "P5 pip platform tags"
export PYTHONPATH=/usr/lib/python3/dist-packages
out=$($PY -m pip debug --verbose 2>&1)
echo "$out" | grep -A3 'Compatible tags' | sed 's/^/INFO /'
if echo "$out" | grep -qE 'armv7l|armv8l|_aarch64$|manylinux'; then echo "RESULT FAIL: pip offers foreign platform tags"; else echo "RESULT ok: no armv7l/armv8l/aarch64/manylinux tags"; fi
expect "linux_aarch64_ilp32 tag" 'linux_aarch64_ilp32' echo "$out"
touch x-1.0-py3-none-linux_armv7l.whl
expect "armv7l wheel refused" 'not a supported wheel' $PY -m pip install --no-index --target t ./x-1.0-py3-none-linux_armv7l.whl
unset PYTHONPATH

step "P5b venv, ensurepip and pip in the venv (Debian's wheels in /usr/share/python-wheels)"
rm -rf venv
check $PY -m venv venv
check venv/bin/python -m pip --version
# a pure-Python package from Debian's wheels; it must import from the venv's own site-packages
check venv/bin/python -m pip install --no-index --find-links /usr/share/python-wheels setuptools
expect "setuptools imports in the venv" '^ok ' venv/bin/python -c 'import setuptools, sys; print("ok", setuptools.__file__)'
expect "venv site-packages in the venv" "$B/venv/lib" venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"], sysconfig.get_paths()["platlib"])'

step "P6 remove and reinstall"
check apt-get remove -y -q python3-ilp32 python3.13-ilp32 python3.13-dev-ilp32
check sh -c "! find /usr/libilp32/python3.13 -name '*.pyc' 2>/dev/null | grep -q ."
check apt-get install -y -q --no-install-recommends "$DEBS"/python3*.deb
check $PY -c 'import ssl, sqlite3'
check dpkg --audit
