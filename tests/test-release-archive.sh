#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
VERSION="$(<"$ROOT_DIR/VERSION")"
readonly VERSION
ARCHIVE_ROOT="live-for-speed-linux-$VERSION"
readonly ARCHIVE_ROOT
TMP_ROOT="$(mktemp -d /tmp/lfs-linux-release.XXXXXX)"
readonly TMP_ROOT
trap 'rm -rf "$TMP_ROOT"' EXIT

post_release=0
if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1 &&
   tag_commit="$(git -C "$ROOT_DIR" rev-parse -q --verify "v$VERSION^{}" 2>/dev/null)" &&
   [[ "$tag_commit" != "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]]; then
  post_release=1
  set +e
  "$ROOT_DIR/scripts/build-release-archive.sh" "$TMP_ROOT/guard" >"$TMP_ROOT/guard.out" 2>&1
  guard_status=$?
  set -e
  [[ "$guard_status" -ne 0 ]]
  grep -Fq "Version $VERSION was already released" "$TMP_ROOT/guard.out"
fi

mkdir -p "$TMP_ROOT/one" "$TMP_ROOT/two"
LFS_LINUX_ALLOW_POST_RELEASE_ARCHIVE=1 \
  "$ROOT_DIR/scripts/build-release-archive.sh" "$TMP_ROOT/one" >"$TMP_ROOT/one.sha"
LFS_LINUX_ALLOW_POST_RELEASE_ARCHIVE=1 \
  "$ROOT_DIR/scripts/build-release-archive.sh" "$TMP_ROOT/two" >"$TMP_ROOT/two.sha"
archive_one="$(find "$TMP_ROOT/one" -type f -name '*.tar.gz' -print -quit)"
archive_two="$(find "$TMP_ROOT/two" -type f -name '*.tar.gz' -print -quit)"
[[ -n "$archive_one" && -n "$archive_two" ]]
archive_hash="$(sha256sum "$archive_one" | awk '{print $1}')"
[[ "$archive_hash" == "$(sha256sum "$archive_two" | awk '{print $1}')" ]]
if [[ -f "$ROOT_DIR/packaging/aur/PKGBUILD" && "$post_release" -eq 0 ]]; then
  pinned_hash="$(grep -Eo "sha256sums=\\('[0-9a-f]{64}'\\)" "$ROOT_DIR/packaging/aur/PKGBUILD" | grep -Eo '[0-9a-f]{64}')"
  [[ "$archive_hash" == "$pinned_hash" ]]
fi

listing="$(tar -tzf "$archive_one")"
grep -Fq "$ARCHIVE_ROOT/bin/lfs-linux" <<<"$listing"
grep -Fq "$ARCHIVE_ROOT/bin/lfs-linux-desktop" <<<"$listing"
grep -Fq "$ARCHIVE_ROOT/libexec/lfs-linux-core" <<<"$listing"
if grep -Eq '(^|/)(legacy|artifacts|\.pi-glla|__pycache__)(/|$)|\.py[co]$' <<<"$listing"; then
  printf 'local evidence or generated Python bytecode entered release archive\n' >&2
  exit 1
fi
if grep -Ei '\.(exe|dll|msi|png)$' <<<"$listing"; then
  printf 'runtime or proprietary payload entered release archive\n' >&2
  exit 1
fi

tar -xzf "$archive_one" -C "$TMP_ROOT"
archive_dir="$TMP_ROOT/$ARCHIVE_ROOT"
LFS_LINUX_SOURCE_ARCHIVE=1 "$archive_dir/tests/test-public-static.sh" >/dev/null
"$archive_dir/tests/test-public-core.sh" >/dev/null
"$archive_dir/tests/test-upgrade.sh" >/dev/null
python3 "$archive_dir/tests/test-support-static.py" >/dev/null
python3 "$archive_dir/tests/test-triage-feedback.py" >/dev/null
"$archive_dir/tests/test-website.sh" >/dev/null
make -C "$archive_dir" DESTDIR="$TMP_ROOT/pkgroot" PREFIX=/usr install >/dev/null
"$archive_dir/tests/test-package-boundary.sh" "$TMP_ROOT/pkgroot" >/dev/null

printf '[PASS] release archive is deterministic, self-testing, and excludes local/proprietary evidence\n'
