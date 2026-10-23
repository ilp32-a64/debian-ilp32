#!/bin/bash
# SPDX-License-Identifier: MIT
# Make an apt repository tree from a directory of .debs (unsigned; sign dists/<suite>/Release with
# sign-release.sh on the machine that holds the archive key, then check with verify-release.sh).
#   <repo>/pool/main/*.deb
#   <repo>/dists/<suite>/main/binary-arm64/Packages{,.gz,.xz}
#   <repo>/dists/<suite>/Release
# Usage: make-repo.sh <dir with *.deb> <repo dir>
#   SUITE  default trixie
set -euo pipefail
umask 022
DEBS=$(realpath "${1:?usage: make-repo.sh <debs dir> <repo dir>}")
REPO=$(realpath -m "${2:?usage: make-repo.sh <debs dir> <repo dir>}")
SUITE=${SUITE:-trixie}
B=dists/$SUITE/main/binary-arm64
mkdir -p "$REPO/pool/main" "$REPO/$B"
cp "$DEBS"/*.deb "$REPO/pool/main/"
cd "$REPO"
apt-ftparchive packages pool/main > "$B/Packages"
gzip -9nkf "$B/Packages"
xz -kf "$B/Packages"
apt-ftparchive \
	-o APT::FTPArchive::Release::Origin=ILP32-A64 \
	-o APT::FTPArchive::Release::Label=ILP32-A64 \
	-o APT::FTPArchive::Release::Suite="$SUITE" \
	-o APT::FTPArchive::Release::Codename="$SUITE" \
	-o APT::FTPArchive::Release::Architectures=arm64 \
	-o APT::FTPArchive::Release::Components=main \
	-o APT::FTPArchive::Release::Description="AArch64 ILP32 packages for Debian 13 (unofficial)" \
	release "dists/$SUITE" > Release.tmp
mv Release.tmp "dists/$SUITE/Release"
rm -f "dists/$SUITE/InRelease" "dists/$SUITE/Release.gpg"
echo "repository: $REPO ($(ls pool/main/*.deb | wc -l) packages, suite $SUITE, unsigned)"
