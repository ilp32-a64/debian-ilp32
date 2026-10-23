#!/bin/bash
# SPDX-License-Identifier: MIT
# apt test of the repository on Debian 13 arm64 in QEMU. Uses throwaway test keys (never the
# real archive key) and file: repositories inside the guest:
#   good      signed with the test key        -> apt update and install must work
#   unsigned  no InRelease / Release.gpg      -> apt update must fail
#   wrongkey  signed with another key         -> apt update must fail
#   badindex  Packages changed after signing  -> apt update must fail
#   baddeb    a .deb changed after signing    -> apt install of it must fail
# Needs sudo (loop mount).
# Usage: run-apt-test.sh <work dir with base.img> <dir with *.deb>
#   TC  toolchain prefix (default ~/work/ilp32-glibc/toolchain/out)
set -euo pipefail
WD=$(realpath "${1:?usage: run-apt-test.sh <work dir> <debs dir>}")
DEBS=$(realpath "${2:?usage: run-apt-test.sh <work dir> <debs dir>}")
HERE=$(dirname "$(realpath "$0")")
TOP=$HERE/..
TC=${TC:-$HOME/work/ilp32-glibc/toolchain/out}
T=aarch64-linux-gnu_ilp32
GUEST_REPOS=/ilp32-test/repos
cd "$WD"
rm -rf apt-test && mkdir -p apt-test/bin apt-test/repos apt-test/keyring
A=$WD/apt-test

export GNUPGHOME=$A/gnupg
mkdir -m 0700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key "ILP32 Test Key <test@invalid>" ed25519 sign 1d
gpg --batch --passphrase '' --quick-gen-key "ILP32 Wrong Key <wrong@invalid>" ed25519 sign 1d
TESTKEY=$(gpg --with-colons -K test@invalid | awk -F: '/^fpr/ {print $10; exit}')
WRONGKEY=$(gpg --with-colons -K wrong@invalid | awk -F: '/^fpr/ {print $10; exit}')
gpg --armor --export "$TESTKEY" > "$A/test-key.asc"

KEY_FILE=$A/test-key.asc URIS=file:$GUEST_REPOS/good "$TOP/keyring/build-keyring-deb.sh" "$A/keyring"

"$TOP/repo/make-repo.sh" "$DEBS" "$A/repos/good"
"$TOP/repo/sign-release.sh" "$A/repos/good/dists/trixie/Release" "$TESTKEY"
"$TOP/repo/verify-release.sh" "$A/repos/good" "$A/test-key.asc"
cp -a "$A/repos/good" "$A/relchanged"
echo "X-Changed: yes" >> "$A/relchanged/dists/trixie/Release"
! "$TOP/repo/verify-release.sh" "$A/relchanged" "$A/test-key.asc" || { echo "verify-release.sh accepted a changed Release"; exit 1; }
rm -rf "$A/relchanged"
# gpg 2.4.9 on Windows signs the final newline as part of the text (an extra empty line in
# InRelease); that must still verify.
cp -a "$A/repos/good" "$A/trailblank"
R2=$A/trailblank/dists/trixie
{ cat "$R2/Release"; echo; } > "$A/release-blank"
gpg --batch --yes --local-user "$TESTKEY" --clearsign -o "$R2/InRelease" "$A/release-blank"
"$TOP/repo/verify-release.sh" "$A/trailblank" "$A/test-key.asc"
rm -rf "$A/trailblank" "$A/release-blank"
"$TOP/repo/make-repo.sh" "$DEBS" "$A/repos/unsigned"
"$TOP/repo/make-repo.sh" "$DEBS" "$A/repos/wrongkey"
"$TOP/repo/sign-release.sh" "$A/repos/wrongkey/dists/trixie/Release" "$WRONGKEY"
! "$TOP/repo/verify-release.sh" "$A/repos/wrongkey" "$A/test-key.asc" || { echo "verify-release.sh accepted the wrong key"; exit 1; }
cp -a "$A/repos/good" "$A/repos/badindex"
P=$A/repos/badindex/dists/trixie/main/binary-arm64
printf '\nPackage: evil\nVersion: 1\nArchitecture: arm64\nFilename: pool/main/evil.deb\nSize: 1\nDescription: injected\n' >> "$P/Packages"
rm -f "$P/Packages.gz" "$P/Packages.xz"
cp -a "$A/repos/good" "$A/repos/baddeb"
f=$(ls "$A"/repos/baddeb/pool/main/libgomp1-ilp32_*.deb)
printf 'X' | dd of="$f" bs=1 seek=$(($(stat -c %s "$f") - 1)) conv=notrunc 2>/dev/null

"$TC/bin/$T-gcc" -O2 -o "$A/bin/hello-ilp32" "$HERE/hello.c"
"$TC/bin/$T-g++" -O2 -o "$A/bin/hello++-ilp32" "$HERE/hello++.cc"
"$TC/bin/$T-gcc" -O2 -fopenmp -o "$A/bin/runtime-test" "$HERE/runtime-test.c" -lm -latomic

cp --sparse=always base.img apt-test.img
mkdir -p mnt
sudo mount -o loop apt-test.img mnt
trap 'mountpoint -q "$WD/mnt" && sudo umount "$WD/mnt"' EXIT
sudo mkdir -p mnt/ilp32-test
sudo cp -a "$A/repos" "$A/bin" "$A/keyring" mnt/ilp32-test/
sudo chown -R root:root mnt/ilp32-test
sudo install -m 0755 "$HERE/guest-apt-test.sh" mnt/ilp32-test/guest-apt-test.sh
printf '#!/bin/bash\n./guest-apt-test.sh\n' | sudo tee mnt/ilp32-test/test.sh > /dev/null
sudo chmod 0755 mnt/ilp32-test/test.sh
sudo umount mnt
"$HERE/qemu-boot.sh" apt-test.img | tee apt-test.log
grep -a -E '^(===|RESULT)' apt-test.log
grep -aq ILP32-TEST-END apt-test.log
! grep -aq 'RESULT FAIL' apt-test.log
echo "apt test: all ok"
