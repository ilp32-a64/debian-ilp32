#!/bin/bash
# SPDX-License-Identifier: MIT
# Publish the signed apt repository on GitHub Pages. The gh-pages branch is replaced by a single
# new commit each time (force push), so old packages do not pile up in the history; keep the
# current and at most the previous version of each package in the pool.
#   <site>/apt/{dists,pool}       from make-repo.sh, signed with sign-release.sh
#   <site>/apt/ilp32-a64-archive.asc
#   <site>/index.html, apt/index.html, .nojekyll    added here
# Checks before anything is pushed: the signatures (verify-release.sh) and the packages
# (scan-leaks.sh).
# Usage: publish-pages.sh <site dir> [--push]     without --push, prepare and check only
#   REMOTE    default git@github.com:ilp32-a64/debian-ilp32.git
#   KEY_FILE  archive public key (default keys/ilp32-a64-archive.asc; another key only for tests)
set -euo pipefail
SITE=$(realpath "${1:?usage: publish-pages.sh <site dir> [--push]}")
PUSH=${2:-}
HERE=$(dirname "$(realpath "$0")")
REMOTE=${REMOTE:-git@github.com:ilp32-a64/debian-ilp32.git}
README=https://github.com/ilp32-a64/debian-ilp32#readme
KEY_FILE=${KEY_FILE:-$HERE/../keys/ilp32-a64-archive.asc}

"$HERE/verify-release.sh" "$SITE/apt" "$KEY_FILE"
"$HERE/../tests/scan-leaks.sh" "$SITE/apt/pool/main"
cmp -s "$SITE/apt/ilp32-a64-archive.asc" "$KEY_FILE" ||
	{ echo "apt/ilp32-a64-archive.asc is not the archive key of this repository" >&2; exit 1; }

page() {
	cat <<EOF
<!doctype html>
<meta charset="utf-8">
<title>ILP32-A64 apt repository</title>
<p>AArch64 ILP32 packages for Debian 13 (unofficial). See <a href="$README">github.com/ilp32-a64/debian-ilp32</a>.</p>
EOF
}
page > "$SITE/index.html"
page > "$SITE/apt/index.html"
: > "$SITE/.nojekyll"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
git init -q -b gh-pages "$W"
cp -a "$SITE"/. "$W"/
cd "$W"
git add -A
# git rc (where installed) records the commit in off hours, as for every other commit.
if command -v git-rc > /dev/null; then commit=(git rc); else commit=(git commit); fi
"${commit[@]}" -q -m "apt repository $(sed -n 's/^Date: //p' apt/dists/*/Release | head -1)"
git log --format='%h %ad %ae %s' --date=iso
git ls-files | sed 's/^/  /'
du -sh --exclude=.git .
if [ "$PUSH" = --push ]; then
	git push --force "$REMOTE" gh-pages
else
	echo "checked; not pushed (add --push to publish)"
fi
