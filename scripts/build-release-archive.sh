#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
VERSION="$(<"$ROOT_DIR/VERSION")"
readonly VERSION
readonly PROJECT_SLUG='live-for-speed-linux'
readonly ARCHIVE_NAME="$PROJECT_SLUG-$VERSION.tar.gz"
readonly OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
readonly SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1786665600}"
readonly EXECUTABLE_PATHS="$ROOT_DIR/scripts/release-executable-paths.txt"
TMP_ROOT=''
readonly -a ENTRIES=(
  .github
  VERSION
  LICENSE
  Makefile
  README.md
  CONTRIBUTING.md
  SECURITY.md
  SUPPORT.md
  bin
  libexec
  share
  docs
  packaging/debian
  scripts
  tests
  website
)

if [[ "${LFS_LINUX_ALLOW_POST_RELEASE_ARCHIVE:-0}" != '1' ]] &&
   git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  tag_commit="$(git -C "$ROOT_DIR" rev-parse -q --verify "v$VERSION^{}" 2>/dev/null || true)"
  if [[ -n "$tag_commit" ]] && {
       [[ "$tag_commit" != "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]] ||
       [[ -n "$(git -C "$ROOT_DIR" status --porcelain -- "${ENTRIES[@]}")" ]];
     }; then
    printf 'Version %s was already released; bump VERSION before building another public archive with that name.\n' "$VERSION" >&2
    exit 1
  fi
fi

command -v python3 >/dev/null 2>&1 || {
  printf 'error: python3 is required to validate the source archive boundary\n' >&2
  exit 1
}
python3 "$ROOT_DIR/scripts/check-source-boundary.py" "$ROOT_DIR" "${ENTRIES[@]}"

cleanup() {
  [[ -z "$TMP_ROOT" ]] || rm -rf --one-file-system -- "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$ARCHIVE_NAME"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lfs-linux-release-stage.XXXXXX")"
readonly TMP_ROOT
readonly STAGED_PROJECT="$TMP_ROOT/$PROJECT_SLUG-$VERSION"
mkdir -p "$STAGED_PROJECT"
for entry in "${ENTRIES[@]}"; do
  mkdir -p "$STAGED_PROJECT/$(dirname "$entry")"
  cp -a -- "$ROOT_DIR/$entry" "$STAGED_PROJECT/$entry"
done
find "$STAGED_PROJECT" -type d -name __pycache__ -prune -exec rm -rf -- {} +
find "$STAGED_PROJECT" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
find "$STAGED_PROJECT" -type d -exec chmod 0755 {} +
find "$STAGED_PROJECT" -type f -exec chmod 0644 {} +
declare -A executable_seen=()
while IFS= read -r executable; do
  [[ -n "$executable" && "$executable" != /* && "$executable" != '..' && \
     "$executable" != ../* && "$executable" != */../* && "$executable" != */.. && \
     -z "${executable_seen[$executable]+present}" ]] || {
    printf 'error: invalid release executable allowlist entry: %s\n' "$executable" >&2
    exit 1
  }
  executable_seen["$executable"]=1
  [[ -f "$STAGED_PROJECT/$executable" && ! -L "$STAGED_PROJECT/$executable" ]] || {
    printf 'error: release executable allowlist path is not a regular file: %s\n' "$executable" >&2
    exit 1
  }
  chmod 0755 "$STAGED_PROJECT/$executable"
done <"$EXECUTABLE_PATHS"
(
  cd "$STAGED_PROJECT"
  tar \
    --sort=name \
    --format=ustar \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --transform="s,^,$PROJECT_SLUG-$VERSION/," \
    -cf - "${ENTRIES[@]}" |
    gzip -n -9 >"$OUTPUT_DIR/$ARCHIVE_NAME"
)

printf '%s  %s\n' "$(sha256sum "$OUTPUT_DIR/$ARCHIVE_NAME" | awk '{print $1}')" "$OUTPUT_DIR/$ARCHIVE_NAME"
