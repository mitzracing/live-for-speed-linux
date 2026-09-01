#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
readonly SOURCE_DIR="${LFS_LINUX_COMPAT_SOURCE_DIR:-/source}"

if [[ "${LFS_LINUX_DISPOSABLE_CONTAINER:-0}" != 1 ||
      ! -e /.dockerenv && ! -e /run/.containerenv ]]; then
  printf 'error: compatibility harness is restricted to an explicitly marked disposable container\n' >&2
  exit 1
fi
if [[ "$(id -u)" -ne 0 ]]; then
  printf 'error: compatibility harness must run as root inside that disposable container\n' >&2
  exit 1
fi
if [[ ! -f "$SOURCE_DIR/VERSION" ]]; then
  printf 'error: source tree not found at %s\n' "$SOURCE_DIR" >&2
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends \
  appstream bash ca-certificates coreutils curl desktop-file-utils dpkg-dev file \
  findutils gawk grep libarchive-tools libxml2-utils make passwd procps python3 \
  python3-yaml sed shellcheck tar util-linux xz-utils 7zip

id -u lfstest >/dev/null 2>&1 || useradd --create-home --uid 2000 --shell /bin/bash lfstest
rm -rf /work /tmp/lfs-test-runtime
mkdir -p /work /tmp/lfs-test-runtime
chmod 0700 /tmp/lfs-test-runtime
tar -C "$SOURCE_DIR" --exclude=.git --exclude=artifacts -cf - . | tar -C /work -xf -
chown -R lfstest:lfstest /work /tmp/lfs-test-runtime

runuser -u lfstest -- env \
  HOME=/home/lfstest \
  XDG_RUNTIME_DIR=/tmp/lfs-test-runtime \
  bash -c '
    set -Eeuo pipefail
    cd /work
    ./tests/test-public-static.sh
    ./tests/test-public-core.sh
    ./tests/test-upgrade.sh
    python3 tests/test-support-static.py
    python3 tests/test-triage-feedback.py
    python3 tests/test-upstream-drift.py
    make package-check
    make deb-check
    shellcheck bin/* libexec/lfs-linux-core packaging/debian/*.sh scripts/*.sh tests/*.sh
    printf "DISTRO_COMPATIBILITY=PASS\n"
  '
