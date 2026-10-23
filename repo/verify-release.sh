#!/bin/bash
# SPDX-License-Identifier: MIT
# Check the signatures of a repository before publishing it: InRelease and Release.gpg must be
# valid signatures by the archive key, and InRelease must carry the repository's Release file
# (so a signature made for another Release cannot slip through). Trailing blank lines are
# ignored in that comparison: gpg 2.4.9 (Git Bash on Windows) signs the final newline of the
# file as part of the text and so adds an empty line before the signature, which gpg 2.4.4 on
# Linux does not; apt reads both the same way.
# Usage: verify-release.sh <repo dir> [armored public key]
#   default key: keys/ilp32-a64-archive.asc of this repository
#   SUITE  default trixie
set -euo pipefail
REPO=${1:?usage: verify-release.sh <repo dir> [public key]}
KEY=${2:-$(dirname "$0")/../keys/ilp32-a64-archive.asc}
R=$REPO/dists/${SUITE:-trixie}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GNUPGHOME=$W/gnupg
mkdir -p "$GNUPGHOME" && chmod 0700 "$GNUPGHOME" 2>/dev/null || true
for f in Release InRelease Release.gpg; do
	[ -f "$R/$f" ] || { echo "missing $R/$f" >&2; exit 1; }
done
gpg --batch --quiet --dearmor -o "$W/key.gpg" < "$KEY"
gpgv --keyring "$W/key.gpg" "$R/Release.gpg" "$R/Release"
gpgv --keyring "$W/key.gpg" --output "$W/signed" "$R/InRelease"
# strip_trailing_blank <file>: the file without trailing empty lines
strip_trailing_blank() { awk '/^$/ { n++; next } { while (n > 0) { print ""; n-- } print }' "$1"; }
cmp -s <(strip_trailing_blank "$W/signed") <(strip_trailing_blank "$R/Release") ||
	{ echo "InRelease does not carry this Release file" >&2; exit 1; }
echo "signatures ok: $R"
