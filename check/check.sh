#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Builds the package in DIR (default: current directory) with makepkg as a non-root user in the
# Containerfile image, runs namcap on PKGBUILD and package, and fails when .SRCINFO is out of date.
# --write-srcinfo rewrites .SRCINFO instead; --update-sums also refreshes the PKGBUILD checksums.
# Usage: check.sh [--update-sums] [--write-srcinfo] [DIR]   (CONTAINER_ENGINE overrides podman)
set -eu

engine=${CONTAINER_ENGINE:-podman}
here=$(cd "$(dirname "$0")" && pwd)
write=
sums=
while [ $# -gt 0 ]; do
    case $1 in
        --write-srcinfo) write=1 ;;
        --update-sums) sums=1; write=1 ;;
        -*) echo "usage: $0 [--update-sums] [--write-srcinfo] [DIR]" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
root=$(cd "${1:-.}" && pwd)
[ -f "$root/PKGBUILD" ] || { echo "no PKGBUILD in $root" >&2; exit 2; }
work=$root/build

# Files the build user leaves behind are owned by a subordinate uid under rootless podman.
cleanup() { "$engine" unshare rm -rf "$work" 2>/dev/null || rm -rf "$work"; }
cleanup
trap cleanup EXIT
mkdir -p "$work"
# Only tracked top-level files are sources, so local leftovers cannot leak into the build.
git -C "$root" ls-files -z | tr '\0' '\n' | grep -v / | while IFS= read -r f; do
    cp "$root/$f" "$work/"
done
chmod -R a+rwX "$work"

"$engine" build -q -t aur-ci-check -f "$here/Containerfile" "$here" >/dev/null
# shellcheck disable=SC2016 # the script expands inside the container
"$engine" run --rm -e SUMS="$sums" -v "$work:/pkg:Z" aur-ci-check sh -eu -c '
    if [ -n "$SUMS" ]; then su builder -c "cd /pkg && updpkgsums"; fi
    su builder -c "cd /pkg && makepkg -f --nodeps --nocolor && makepkg --printsrcinfo >.SRCINFO"
    cd /pkg
    echo "== namcap PKGBUILD"
    namcap PKGBUILD
    echo "== namcap package"
    namcap ./*.pkg.tar.zst
    echo "== package contents"
    for p in ./*.pkg.tar.zst; do bsdtar -tvf "$p" | tail -n 20; done
'

[ -z "$sums" ] || cp "$work/PKGBUILD" "$root/PKGBUILD"
if [ -n "$write" ]; then
    cp "$work/.SRCINFO" "$root/.SRCINFO"
elif ! diff -u "$root/.SRCINFO" "$work/.SRCINFO"; then
    echo ".SRCINFO is out of date: run check.sh --write-srcinfo" >&2
    exit 1
fi
