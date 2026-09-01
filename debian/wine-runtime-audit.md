# Pinned Wine 11.15-1 Debian ABI audit

## Scope

Audited artifact:
`wine-11.15-1-x86_64.pkg.tar.zst` (81,887,639 bytes), SHA-256
`5ee6a5522f81aba8441474c833552dd8f86bc9b9927c4efc9cb9251121124af4`.
This is the exact immutable Arch Linux Archive package pinned by wrapper 0.3.2.
Audit ran on Debian unstable amd64 on 2026-09-01. It parsed every runtime ELF
file and every member of the Unix static archives with `readelf`; it did not
execute Wine while collecting dependencies. Mandatory tool or parse failures
stop the audit. Private `DT_NEEDED` edges resolve per consumer directory rather
than through a global basename set. Reproduce from an unpacked, hash- and
signature-verified package with:

```
debian/tools/audit-wine-runtime.py ROOT result.json
```

The resulting JSON used for this report has SHA-256
`70e5b5829f4dc9b07342bf9e0baf9cf0573201f34ee19d8f8249b887837a9e5a`.

## Results

* 45 runtime ELF files; every file is `ELF64 / x86-64`.
* 256 `usr/lib/wine/x86_64-unix` static archives contain 33,896 audited
  `ELF64 / x86-64` members. Another 517 import archives are confined to the
  reviewed `i386-windows` and `x86_64-windows` directories and are not runtime
  ELF inputs; a static archive anywhere else fails the audit.
* No ELF32 Unix runtime file or Unix static-archive member exists.
* All executable interpreters are `/lib64/ld-linux-x86-64.so.2`.
* Highest required glibc symbol is `GLIBC_2.38`.
* Highest required GCC runtime symbol is `GCC_3.3.1`.
* No `GLIBCXX` or `CXXABI` symbol requirement was found.
* 32 distinct `DT_NEEDED` names: 2 resolve inside the private Wine tree,
  26 resolve to installed Debian unstable libraries, and 4 do not resolve in
  the tested host profile. No private provider was unreachable from a
  consumer's recorded search path.
* With the resolved host libraries present, the pinned executables report
  `wine-11.15` and `Wine 11.15` from `wine --version` and
  `wineserver --version`.

Resolved external SONAMEs map to these Debian packages:

```
libasound2t64
libc6
libgcc-s1
libglib2.0-0t64
libgphoto2-6t64
libgphoto2-port12t64
libgstreamer-plugins-base1.0-0
libgstreamer1.0-0
libpcsclite1
libpulse0
libsane1
libudev1
libusb-1.0-0
libwayland-client0
libwayland-egl1
libx11-6
libxext6
libxkbcommon0
libxkbregistry0
ocl-icd-libopencl1
```

`libc6` owns libc, libm, libresolv, and the dynamic loader. GLib and GStreamer
packages each own multiple required SONAMEs. Runtime Vulkan use is not exposed
as an ELF `DT_NEEDED` edge because Wine/DXVK load it dynamically; the package
therefore retains explicit `libvulkan1` and Vulkan ICD dependencies and
recommends `vulkan-tools` for diagnostics. `debian/control` names the audited
host-library packages directly instead of depending on Debian's incompatible
Wine as an indirect library bundle.

## Unresolved optional Wine modules

| Required SONAME | Arch Wine consumer | Debian unstable result |
|---|---|---|
| `libavcodec.so.63` | `usr/lib/wine/x86_64-unix/winedmo.so` | unavailable; Debian currently provides `libavcodec.so.62` |
| `libavformat.so.63` | `usr/lib/wine/x86_64-unix/winedmo.so` | unavailable; Debian currently provides `libavformat.so.62` |
| `libavutil.so.61` | `usr/lib/wine/x86_64-unix/winedmo.so` | unavailable; Debian currently provides `libavutil.so.60` |
| `libpcap.so.1` | `usr/lib/wine/x86_64-unix/wpcap.so` | unavailable under this SONAME; Debian provides `libpcap.so.0.8` |

These modules provide Windows multimedia transforms and packet capture. Live
for Speed's audited launch path does not use packet capture. Prior Debian 13
and Ubuntu 24.04 C20 GUI tests also completed without loading these optional
modules. `libsane1` is now a direct dependency and resolves the previously
missing scanner-module edge. That behavioral evidence
does not make the package ABI-complete: immutable Arch Wine remains partly
incompatible with Debian unstable's current FFmpeg and libpcap SONAMEs.

## Binary signature and source correspondence

The immutable package has a 119-byte detached signature with SHA-256
`c137f4dc493c7f8f00b47e42a014d19cdbbcac8b7daed41948b8f8148e3edc80`.
`gpgv` verifies it against exact fingerprint
`D2E95FEC015CF1F911AAAB0C3D4C5008BB5C8D29`, Peter Jung
`<ptr1337@archlinux.org>`, before extraction. The 1,527-byte keyring shipped by
the Debian package has SHA-256
`c3186f2f7bdbe1cd02002dc84bce781580e4edc49fdc3ad848096af6768f3a89`.
It was exported from Debian's `archlinux-keyring` 0~20260727-1, corresponding
to signed Arch keyring tag `20260727` and commit
`cb5bbe4f36edae7a6bc7b3e373714dcde2cba7ae`. Arch's official packager page
publishes the same identity and fingerprint. This proves the pinned binary was
signed by the named Arch packager; it is not a reproducible-build attestation.

## Submission decision gate

Debian unstable cannot satisfy the four Arch SONAME mismatches above. Do not claim
complete ABI compatibility.

Before upload, obtain Debian Games Team or sponsor agreement on one path:

1. accept the two optional unusable module groups as irrelevant to this
   game-specific launcher;
2. prune those modules after archive verification, regenerate the audited Wine
   manifest, and re-run clean GUI tests; or
3. replace the foreign runtime with an exact Debian-native Wine profile and
   re-run the complete compatibility and updater test matrix.

The project does not mirror or redistribute this Wine binary. Exact source,
Arch recipe, signed tags, hashes, and licensing are recorded in
`debian/README.source`.
