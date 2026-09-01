#!/usr/bin/env bash
# Variables and helper functions below are consumed by sourced production functions.
# shellcheck disable=SC2034,SC2317,SC2329
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT_DIR/libexec/lfs-linux-core"
FIXTURES="$ROOT_DIR/tests/fixtures/runtime-trust"
TMP_ROOT="$(mktemp -d /tmp/lfs-runtime-trust.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

signature_functions="$TMP_ROOT/signature-functions.sh"
archive_functions="$TMP_ROOT/archive-functions.sh"
sed -n '/^verify_wine_package_signature() {/,/^ensure_wine_runtime() {/p' "$CORE" | sed '$d' >"$signature_functions"
sed -n '/^archive_member_listing_is_safe() {/,/^download_verified() {/p' "$CORE" | sed '$d' >"$archive_functions"
grep -Fq 'gpgv --status-fd 1' "$signature_functions"
grep -Fq 'preflight_bsdtar_archive()' "$archive_functions"
grep -Fq 'extract_bsdtar_archive()' "$archive_functions"

(
  cd "$FIXTURES"
  sha256sum -c <<'EOF'
b479b43482b9fd4c1cb87437ccc669b3940697cd7e76aebd5d175d2ac247789a  combined-keys.pgp
65404fd43fdd16d97718c40237811252a864267d3b60d36ae2827648754b440e  payload.txt
1b6e016e53dc79db581f5659199742b529bf5c88194a2375f49c300f5725cabb  valid.fingerprint
b1bf25dc93f3a3428d7f98a8df161568af5685c6c9fe577af928a053c561c2bb  valid.sig
14733ee043aa7fee19d657dbfba1a5a1580b269fdbd5e65eeca498607d4159d4  wrong.fingerprint
c947aab85a8c6e0f2caaafeefae35c7fb87043776fad4a5f04bf60cf1a5fa471  wrong.sig
EOF
)

valid_fingerprint="$(cat "$FIXTURES/valid.fingerprint")"
key_size="$(stat -c %s "$FIXTURES/combined-keys.pgp")"
key_hash="$(sha256sum "$FIXTURES/combined-keys.pgp" | awk '{print $1}')"

run_signature_check() (
  set -Eeuo pipefail
  local signature="$1" payload="$2" expected_fingerprint="$3" mode="${4:-real}"
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }
  verify_file() {
    local label="$1" path="$2" expected_size="$3" expected_hash="$4"
    [[ -f "$path" ]] || die "$label is missing"
    [[ "$(stat -c %s "$path")" == "$expected_size" ]] || die "$label size drift"
    [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_hash" ]] || die "$label checksum drift"
  }
  # shellcheck source=/dev/null
  source "$signature_functions"
  WINE_RUNTIME_VERSION='test'
  WINE_SIGNING_KEY="$FIXTURES/combined-keys.pgp"
  WINE_SIGNING_KEY_SIZE="$key_size"
  WINE_SIGNING_KEY_SHA256="$key_hash"
  WINE_SIGNING_KEY_FINGERPRINT="$expected_fingerprint"
  WINE_PACKAGE_SIGNATURE="$signature"
  WINE_PACKAGE_SIGNATURE_SIZE="$(stat -c %s "$signature")"
  WINE_PACKAGE_SIGNATURE_SHA256="$(sha256sum "$signature" | awk '{print $1}')"
  WINE_PACKAGE="$payload"
  if [[ "$mode" == 'missing-validsig' ]]; then
    PATH="$TMP_ROOT/no-validsig-bin:$PATH"
  fi
  verify_wine_package_signature
)

mkdir -p "$TMP_ROOT/no-validsig-bin"
cat >"$TMP_ROOT/no-validsig-bin/gpgv" <<'EOF'
#!/bin/sh
printf '%s\n' '[GNUPG:] NEWSIG' '[GNUPG:] GOODSIG 0000000000000000 fixture'
exit 0
EOF
chmod 0755 "$TMP_ROOT/no-validsig-bin/gpgv"

run_signature_check "$FIXTURES/valid.sig" "$FIXTURES/payload.txt" "$valid_fingerprint"

set +e
run_signature_check "$FIXTURES/wrong.sig" "$FIXTURES/payload.txt" "$valid_fingerprint" >"$TMP_ROOT/wrong-signer.out" 2>&1
wrong_status=$?
set -e
[[ "$wrong_status" -ne 0 ]]
grep -Fq 'unexpected signer' "$TMP_ROOT/wrong-signer.out"

cp "$FIXTURES/payload.txt" "$TMP_ROOT/tampered-payload.txt"
printf 'tamper\n' >>"$TMP_ROOT/tampered-payload.txt"
set +e
run_signature_check "$FIXTURES/valid.sig" "$TMP_ROOT/tampered-payload.txt" "$valid_fingerprint" >"$TMP_ROOT/bad-signature.out" 2>&1
bad_status=$?
set -e
[[ "$bad_status" -ne 0 ]]
grep -Fq 'signature is invalid' "$TMP_ROOT/bad-signature.out"

set +e
run_signature_check "$FIXTURES/valid.sig" "$FIXTURES/payload.txt" "$valid_fingerprint" missing-validsig >"$TMP_ROOT/missing-validsig.out" 2>&1
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]]
grep -Fq 'unexpected signer' "$TMP_ROOT/missing-validsig.out"

python3 - "$TMP_ROOT" <<'PY'
import io
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])

def add_regular(archive, name, content=b"fixture\n"):
    info = tarfile.TarInfo(name)
    info.size = len(content)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(content))

with tarfile.open(root / "safe.tar", "w") as archive:
    directory = tarfile.TarInfo("safe")
    directory.type = tarfile.DIRTYPE
    directory.mode = 0o755
    archive.addfile(directory)
    add_regular(archive, "safe/file")
    link = tarfile.TarInfo("safe/link")
    link.type = tarfile.SYMTYPE
    link.linkname = "file"
    archive.addfile(link)

with tarfile.open(root / "absolute.tar", "w") as archive:
    add_regular(archive, "/tmp/lfs-runtime-trust-absolute-outside")

with tarfile.open(root / "traversal.tar", "w") as archive:
    add_regular(archive, "../../outside-sentinel")

with tarfile.open(root / "escaping-symlink.tar", "w") as archive:
    link = tarfile.TarInfo("safe/link")
    link.type = tarfile.SYMTYPE
    link.linkname = "../../outside-sentinel"
    archive.addfile(link)

with tarfile.open(root / "hardlink.tar", "w") as archive:
    add_regular(archive, "safe/file")
    link = tarfile.TarInfo("safe/hard")
    link.type = tarfile.LNKTYPE
    link.linkname = "safe/file"
    archive.addfile(link)

with tarfile.open(root / "duplicate.tar", "w") as archive:
    add_regular(archive, "safe/file", b"first\n")
    add_regular(archive, "safe//file", b"second\n")

with tarfile.open(root / "fifo.tar", "w") as archive:
    fifo = tarfile.TarInfo("safe/fifo")
    fifo.type = tarfile.FIFOTYPE
    fifo.mode = 0o600
    archive.addfile(fifo)

with tarfile.open(root / "conflict.tar", "w") as archive:
    add_regular(archive, "safe/existing", b"replacement\n")
    add_regular(archive, "safe/new", b"new\n")
PY

run_archive_rejected() {
  local name="$1" archive="$2" destination="$TMP_ROOT/rejected-$1" status
  mkdir -p "$destination"
  printf 'unchanged\n' >"$destination/sentinel"
  set +e
  (
    set -Eeuo pipefail
    die() { printf 'error: %s\n' "$*" >&2; exit 1; }
    # shellcheck source=/dev/null
    source "$archive_functions"
    extract_bsdtar_archive "$archive" "$destination" "$name fixture"
  ) >"$TMP_ROOT/$name.out" 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]]
  grep -Fq 'unsafe or unreadable archive members' "$TMP_ROOT/$name.out"
  [[ "$(cat "$destination/sentinel")" == 'unchanged' ]]
  [[ "$(find "$destination" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]]
  [[ ! -e "$TMP_ROOT/outside-sentinel" ]]
  [[ ! -e /tmp/lfs-runtime-trust-absolute-outside ]]
}

run_archive_rejected absolute "$TMP_ROOT/absolute.tar"
run_archive_rejected traversal "$TMP_ROOT/traversal.tar"
run_archive_rejected escaping-symlink "$TMP_ROOT/escaping-symlink.tar"
run_archive_rejected hardlink "$TMP_ROOT/hardlink.tar"
run_archive_rejected duplicate "$TMP_ROOT/duplicate.tar"
run_archive_rejected fifo "$TMP_ROOT/fifo.tar"

safe_destination="$TMP_ROOT/safe-destination"
mkdir -p "$safe_destination"
(
  set -Eeuo pipefail
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$archive_functions"
  extract_bsdtar_archive "$TMP_ROOT/safe.tar" "$safe_destination" 'safe fixture'
)
[[ "$(cat "$safe_destination/safe/file")" == 'fixture' ]]
[[ -L "$safe_destination/safe/link" ]]
[[ "$(readlink "$safe_destination/safe/link")" == 'file' ]]

conflict_destination="$TMP_ROOT/conflict-destination"
mkdir -p "$conflict_destination/safe"
printf 'original\n' >"$conflict_destination/safe/existing"
set +e
(
  set -Eeuo pipefail
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$archive_functions"
  extract_bsdtar_archive "$TMP_ROOT/conflict.tar" "$conflict_destination" 'conflict fixture'
) >"$TMP_ROOT/conflict.out" 2>&1
conflict_status=$?
set -e
[[ "$conflict_status" -ne 0 ]]
grep -Fq 'extraction destination is not empty' "$TMP_ROOT/conflict.out"
[[ "$(cat "$conflict_destination/safe/existing")" == 'original' ]]
[[ ! -e "$conflict_destination/safe/new" ]]
[[ ! -e "$TMP_ROOT/outside-sentinel" ]]

unreadable_destination="$TMP_ROOT/unreadable-destination"
mkdir -p "$unreadable_destination"
chmod 000 "$unreadable_destination"
set +e
(
  set -Eeuo pipefail
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$archive_functions"
  extract_bsdtar_archive "$TMP_ROOT/safe.tar" "$unreadable_destination" 'unreadable fixture'
) >"$TMP_ROOT/unreadable.out" 2>&1
unreadable_status=$?
set -e
chmod 0700 "$unreadable_destination"
[[ "$unreadable_status" -ne 0 ]]
grep -Fq 'extraction destination inspection failed' "$TMP_ROOT/unreadable.out"
[[ -z "$(find "$unreadable_destination" -mindepth 1 -print -quit)" ]]

printf '[PASS] Wine signature decisions and bsdtar path/link/type/no-overwrite boundaries pass\n'
