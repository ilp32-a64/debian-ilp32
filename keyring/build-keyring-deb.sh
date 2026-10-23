#!/bin/bash
# SPDX-License-Identifier: MIT
# Build ilp32-a64-archive-keyring: the archive signing key and the apt source of the ILP32-A64
# repository, so that installing this one package is enough to "apt install" the others.
#   /usr/share/keyrings/ilp32-a64-archive.gpg       binary keyring (gpg --dearmor)
#   /etc/apt/sources.list.d/ilp32-a64.sources        deb822 source with Signed-By
#
# Usage: build-keyring-deb.sh [output dir]
#   KEY_FILE  armored public key (default keys/ilp32-a64-archive.asc of this repository)
#   URIS      repository URL (default https://ilp32-a64.github.io/debian-ilp32/apt)
#   SUITE     default trixie
#   VERSION   package version (default 2026.10.23)
set -euo pipefail
umask 022
HERE=$(dirname "$(realpath "$0")")
KEY_FILE=${KEY_FILE:-$HERE/../keys/ilp32-a64-archive.asc}
URIS=${URIS:-https://ilp32-a64.github.io/debian-ilp32/apt}
SUITE=${SUITE:-trixie}
VERSION=${VERSION:-2026.10.24}
OUT=$(realpath -m "${1:-out}")
NAME=ilp32-a64-archive-keyring
MAINT="liviyifan <344781483+liviyifan@users.noreply.github.com>"
KEYRING=/usr/share/keyrings/ilp32-a64-archive.gpg

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
D=$W/$NAME
export GNUPGHOME=$W/gnupg
mkdir -m 0700 "$GNUPGHOME"
mkdir -p "$D/DEBIAN" "$D/usr/share/keyrings" "$D/etc/apt/sources.list.d" "$D/usr/share/doc/$NAME" "$OUT"

gpg --batch --yes --dearmor -o "$D$KEYRING" < "$KEY_FILE"
chmod 0644 "$D$KEYRING"
cat > "$D/etc/apt/sources.list.d/ilp32-a64.sources" <<EOF
# ILP32-A64: AArch64 ILP32 packages for Debian 13 (unofficial).
Types: deb
URIs: $URIS
Suites: $SUITE
Components: main
Architectures: arm64
Signed-By: $KEYRING
EOF
echo /etc/apt/sources.list.d/ilp32-a64.sources > "$D/DEBIAN/conffiles"

cat <<EOF | gzip -9n > "$D/usr/share/doc/$NAME/changelog.Debian.gz"
$NAME ($VERSION) unstable; urgency=medium

  * Archive key $(gpg --show-keys --with-colons "$KEY_FILE" | awk -F: '/^fpr/ {print $10; exit}').

 -- $MAINT  $(date -R)
EOF

cat > "$D/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: all
Maintainer: $MAINT
Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)
Section: misc
Priority: optional
Homepage: https://github.com/ilp32-a64/debian-ilp32
Description: archive key and apt source of the ILP32-A64 repository
 Installs the public key that signs the ILP32-A64 apt repository
 (AArch64 ILP32 runtime libraries and kernel for Debian 13) and an apt
 source for it in /etc/apt/sources.list.d/ilp32-a64.sources.
EOF
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z |
	xargs -0r md5sum > DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT/${NAME}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${NAME}_${VERSION}_all.deb"
