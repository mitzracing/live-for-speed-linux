#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
VERSION="$(<"$ROOT_DIR/VERSION")"
readonly VERSION
readonly PROJECT_SLUG='live-for-speed-linux'
readonly ARCHIVE_NAME="$PROJECT_SLUG-$VERSION.tar.gz"
OUTPUT_DIR="$(realpath -m -- "${1:-$ROOT_DIR/dist}")"
readonly OUTPUT_DIR
readonly SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1786665600}"
STAGING=''
trap '[[ -z "$STAGING" ]] || rm -rf -- "$STAGING"' EXIT
readonly -a ENTRIES=(
  .github
  AGENTS.md
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

mkdir -p "$OUTPUT_DIR"
STAGING="$(mktemp -d /tmp/lfs-linux-source.XXXXXX)"
for entry in "${ENTRIES[@]}"; do
  mkdir -p "$STAGING/$(dirname "$entry")"
  cp -a -- "$ROOT_DIR/$entry" "$STAGING/$entry"
done
# Git does not record directory modes; normalize only the disposable copy.
find "$STAGING" -mindepth 1 -type d -exec chmod 0755 -- {} +
# Preserve recorded release modes without modifying the owner's working tree.
# Extracted source archives already carry these modes and need no Git metadata.
if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r -d '' entry; do
    header="${entry%%$'\t'*}"
    path="${entry#*$'\t'}"
    mode="${header%% *}"
    [[ -f "$STAGING/$path" && ! -L "$STAGING/$path" ]] || continue
    case "$mode" in
      100644) chmod 0644 -- "$STAGING/$path" ;;
      100755) chmod 0755 -- "$STAGING/$path" ;;
    esac
  done < <(git -C "$ROOT_DIR" ls-files --stage -z)
fi
rm -f "$OUTPUT_DIR/$ARCHIVE_NAME"
(
  cd "$STAGING"
  tar \
    --sort=name \
    --format=ustar \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --exclude='__pycache__' \
    --exclude='*/__pycache__' \
    --exclude='*.py[co]' \
    --transform="s,^,$PROJECT_SLUG-$VERSION/," \
    -cf - "${ENTRIES[@]}" |
    gzip -n -9 >"$OUTPUT_DIR/$ARCHIVE_NAME"
)

printf '%s  %s\n' "$(sha256sum "$OUTPUT_DIR/$ARCHIVE_NAME" | awk '{print $1}')" "$OUTPUT_DIR/$ARCHIVE_NAME"
