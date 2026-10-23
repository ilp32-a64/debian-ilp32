#!/bin/bash
# SPDX-License-Identifier: MIT
# Sign an apt Release file: writes InRelease (inline signature) and Release.gpg (detached
# signature) next to it. Only the Release file is needed, so this runs on the machine that holds
# the archive key (Linux or Git Bash on Windows); copy the two outputs back to the repository.
# Usage: sign-release.sh <Release file> [key id or fingerprint]
#   default key: D5723B340CBE7C99209182439C6A5E841E289B20 (ILP32-A64 Archive Signing Key)
set -euo pipefail
REL=${1:?usage: sign-release.sh <Release file> [key]}
KEY=${2:-D5723B340CBE7C99209182439C6A5E841E289B20}
DIR=$(dirname "$REL")
[ -f "$REL" ] || { echo "no such file: $REL" >&2; exit 1; }
grep -q '^SHA256:' "$REL" || { echo "$REL does not look like an apt Release file" >&2; exit 1; }
gpg --batch --yes --local-user "$KEY" --digest-algo SHA512 --clearsign -o "$DIR/InRelease" "$REL"
gpg --batch --yes --local-user "$KEY" --digest-algo SHA512 --armor --detach-sign -o "$DIR/Release.gpg" "$REL"
gpg --batch --verify "$DIR/Release.gpg" "$REL"
echo "signed with $KEY: $DIR/InRelease $DIR/Release.gpg"
