#!/usr/bin/env python3
"""Audit the pinned Arch Wine runtime against one Debian amd64 host profile."""

import collections
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


class AuditError(RuntimeError):
    pass


def run_checked(*args: str) -> str:
    try:
        completed = subprocess.run(
            args,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as error:
        raise AuditError(f"required audit tool is missing: {args[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or "no diagnostic"
        raise AuditError(f"command failed ({' '.join(args)}): {detail}") from error
    return completed.stdout


def run_probe(*args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as error:
        raise AuditError(f"required audit tool is missing: {args[0]}") from error


def version_key(value: str) -> tuple[int, ...]:
    return tuple(map(int, value.split(".")))


def expand_search_path(value: str, consumer: Path) -> Path:
    expanded = value.replace("${ORIGIN}", str(consumer.parent)).replace(
        "$ORIGIN", str(consumer.parent)
    )
    candidate = Path(expanded)
    if not candidate.is_absolute():
        raise AuditError(
            f"unsupported relative ELF search path {value!r} in {consumer}"
        )
    return candidate.resolve()


def package_owners(path: str) -> list[str]:
    candidates = [path, os.path.realpath(path)]
    lines: list[str] = []
    diagnostics: list[str] = []
    for candidate in dict.fromkeys(candidates):
        result = run_probe("dpkg-query", "-S", candidate)
        if result.returncode == 0:
            lines.extend(result.stdout.splitlines())
        else:
            diagnostics.append(result.stderr.strip() or result.stdout.strip())
    packages = sorted(
        {line.split(": ", 1)[0] for line in lines if ": " in line}
    )
    if not packages:
        detail = "; ".join(filter(None, diagnostics)) or "no package owner"
        raise AuditError(f"cannot map resolved host library {path} to Debian: {detail}")
    return packages


def resolve_dependencies(
    root: Path,
    needed_by_name: dict[str, set[str]],
    providers_by_name: dict[str, set[Path]],
    search_dirs_by_consumer: dict[str, list[Path]],
    system_by_name: dict[str, str],
) -> tuple[
    dict[str, dict[str, object]],
    dict[str, dict[str, object]],
    dict[str, list[str]],
    dict[str, dict[str, object]],
]:
    private: dict[str, dict[str, object]] = {}
    system: dict[str, dict[str, object]] = {}
    unresolved: dict[str, list[str]] = {}
    unreachable_private: dict[str, dict[str, object]] = {}
    owner_cache: dict[str, list[str]] = {}

    for name, consumer_set in sorted(needed_by_name.items()):
        provider_paths = sorted(providers_by_name.get(name, set()))
        host_path = system_by_name.get(name)
        for consumer in sorted(consumer_set):
            allowed_dirs = set(search_dirs_by_consumer[consumer])
            reachable = [
                provider
                for provider in provider_paths
                if provider.parent.resolve() in allowed_dirs
            ]
            if reachable:
                entry = private.setdefault(
                    name, {"providers": set(), "consumers": []}
                )
                entry["providers"].update(reachable)
                entry["consumers"].append(consumer)
                continue

            if provider_paths:
                entry = unreachable_private.setdefault(
                    name,
                    {
                        "providers": [
                            provider.relative_to(root).as_posix()
                            for provider in provider_paths
                        ],
                        "consumers": [],
                    },
                )
                entry["consumers"].append(consumer)
            if not host_path:
                unresolved.setdefault(name, []).append(consumer)
                continue
            if host_path not in owner_cache:
                owner_cache[host_path] = package_owners(host_path)
            entry = system.setdefault(
                name,
                {
                    "path": host_path,
                    "packages": owner_cache[host_path],
                    "consumers": [],
                },
            )
            entry["consumers"].append(consumer)

    for data in private.values():
        data["providers"] = [
            provider.relative_to(root).as_posix()
            for provider in sorted(data["providers"])
        ]
    return private, system, unresolved, unreachable_private


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} UNPACKED_WINE_ROOT OUTPUT.json", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    out_json = Path(sys.argv[2])
    if not root.is_dir():
        raise AuditError(f"Wine root is not a directory: {root}")

    ldconfig = run_checked("ldconfig", "-p")
    system_by_name: dict[str, str] = {}
    for line in ldconfig.splitlines():
        match = re.match(
            r"\s*(\S+)\s+\([^)]*x86-64[^)]*\)\s+=>\s+(\S+)", line
        )
        if match:
            system_by_name.setdefault(match.group(1), match.group(2))
    for loader in (
        "/lib64/ld-linux-x86-64.so.2",
        "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
    ):
        if Path(loader).exists():
            system_by_name.setdefault("ld-linux-x86-64.so.2", loader)
    if not system_by_name:
        raise AuditError("ldconfig returned no amd64 host libraries")

    elfs: list[dict[str, object]] = []
    elf_static_archives: list[dict[str, object]] = []
    non_elf_static_archives = 0
    needed_by_name: dict[str, set[str]] = collections.defaultdict(set)
    glibc_versions: set[str] = set()
    glibcxx_versions: set[str] = set()
    gcc_versions: set[str] = set()
    cxxabi_versions: set[str] = set()
    architectures: collections.Counter[str] = collections.Counter()
    interpreters: set[str] = set()
    providers_by_name: dict[str, set[Path]] = collections.defaultdict(set)
    search_dirs_by_consumer: dict[str, list[Path]] = {}

    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            with path.open("rb") as stream:
                magic = stream.read(8)
        except OSError as error:
            raise AuditError(f"cannot read audit candidate {path}: {error}") from error
        rel = path.relative_to(root).as_posix()
        if magic == b"!<arch>\n":
            if rel.startswith("usr/lib/wine/x86_64-unix/"):
                archive_headers = run_checked("readelf", "-h", str(path))
                classes = re.findall(
                    r"^\s*Class:\s*(\S+)", archive_headers, re.MULTILINE
                )
                machines = re.findall(
                    r"^\s*Machine:\s*(.+)$", archive_headers, re.MULTILINE
                )
                if not classes or len(classes) != len(machines):
                    raise AuditError(
                        f"readelf omitted static archive member headers for {rel}"
                    )
                member_architectures = {
                    f"{elf_class} / {machine.strip()}"
                    for elf_class, machine in zip(classes, machines)
                }
                expected = {"ELF64 / Advanced Micro Devices X86-64"}
                if member_architectures != expected:
                    raise AuditError(
                        f"unexpected static archive architecture in {rel}: "
                        + ", ".join(sorted(member_architectures))
                    )
                elf_static_archives.append(
                    {"path": rel, "elf_member_count": len(classes)}
                )
            elif rel.startswith(
                ("usr/lib/wine/i386-windows/", "usr/lib/wine/x86_64-windows/")
            ):
                non_elf_static_archives += 1
            else:
                raise AuditError(
                    f"static archive outside reviewed Wine ABI directories: {rel}"
                )
            continue
        if magic[:4] != b"\x7fELF":
            continue

        header = run_checked("readelf", "-h", str(path))
        dynamic = run_checked("readelf", "-d", str(path))
        program = run_checked("readelf", "-l", str(path))
        versions = run_checked("readelf", "--version-info", str(path))
        elf_class = re.search(r"^\s*Class:\s*(\S+)", header, re.MULTILINE)
        machine = re.search(r"^\s*Machine:\s*(.+)$", header, re.MULTILINE)
        if not elf_class or not machine:
            raise AuditError(f"readelf omitted class or machine for {rel}")
        architecture = f"{elf_class.group(1)} / {machine.group(1).strip()}"
        architectures[architecture] += 1

        needed = re.findall(r"\(NEEDED\).*?\[(.+?)\]", dynamic)
        sonames = re.findall(r"\(SONAME\).*?\[(.+?)\]", dynamic)
        providers_by_name[path.name].add(path)
        for soname in sonames:
            providers_by_name[soname].add(path)
        for name in needed:
            needed_by_name[name].add(rel)

        search_dirs = [path.parent.resolve()]
        for raw_paths in re.findall(r"\((?:RPATH|RUNPATH)\).*?\[(.+?)\]", dynamic):
            for raw_path in raw_paths.split(":"):
                search_dirs.append(expand_search_path(raw_path, path))
        if path.parent == root / "usr/lib/wine/x86_64-unix":
            search_dirs.append((root / "usr/lib/wine/x86_64-unix").resolve())
        search_dirs_by_consumer[rel] = list(dict.fromkeys(search_dirs))

        interp = re.search(r"Requesting program interpreter:\s*([^\]]+)", program)
        if interp:
            interpreters.add(interp.group(1))
        version_pattern = r"([0-9]+(?:\.[0-9]+)+)"
        glibc_versions.update(
            re.findall(r"\bGLIBC_" + version_pattern + r"\b", versions)
        )
        glibcxx_versions.update(
            re.findall(r"\bGLIBCXX_" + version_pattern + r"\b", versions)
        )
        gcc_versions.update(
            re.findall(r"\bGCC_" + version_pattern + r"\b", versions)
        )
        cxxabi_versions.update(
            re.findall(r"\bCXXABI_" + version_pattern + r"\b", versions)
        )
        elfs.append(
            {
                "path": rel,
                "architecture": architecture,
                "needed": needed,
                "soname": sonames,
                "search_dirs": [
                    directory.relative_to(root).as_posix()
                    if directory.is_relative_to(root)
                    else str(directory)
                    for directory in search_dirs_by_consumer[rel]
                ],
            }
        )

    if not elfs:
        raise AuditError("no ELF files found in Wine runtime")
    if not elf_static_archives:
        raise AuditError("no x86_64 Unix ELF static archives found in Wine runtime")
    unexpected_architectures = {
        architecture
        for architecture in architectures
        if architecture != "ELF64 / Advanced Micro Devices X86-64"
    }
    if unexpected_architectures:
        raise AuditError(
            "unexpected Wine ELF architecture(s): "
            + ", ".join(sorted(unexpected_architectures))
        )
    expected_interpreters = {"/lib64/ld-linux-x86-64.so.2"}
    if not interpreters or not interpreters <= expected_interpreters:
        raise AuditError(
            "unexpected or missing ELF interpreter(s): "
            + ", ".join(sorted(interpreters))
        )

    private, system, unresolved, unreachable_private = resolve_dependencies(
        root,
        needed_by_name,
        providers_by_name,
        search_dirs_by_consumer,
        system_by_name,
    )

    if unreachable_private:
        details = ", ".join(
            f"{name} ({len(data['consumers'])} consumer(s))"
            for name, data in sorted(unreachable_private.items())
        )
        raise AuditError(f"private ELF providers are unreachable: {details}")

    pkginfo = root / ".PKGINFO"
    buildinfo = root / ".BUILDINFO"
    if not pkginfo.is_file() or not buildinfo.is_file():
        raise AuditError("Arch .PKGINFO or .BUILDINFO is missing from runtime root")

    result = {
        "root": str(root),
        "elf_count": len(elfs),
        "elf_static_archive_count": len(elf_static_archives),
        "elf_static_archive_member_count": sum(
            archive["elf_member_count"] for archive in elf_static_archives
        ),
        "non_elf_static_archive_count": non_elf_static_archives,
        "architectures": dict(sorted(architectures.items())),
        "interpreters": sorted(interpreters),
        "needed_names": len(needed_by_name),
        "private_needed": private,
        "system_needed": system,
        "unresolved_needed": unresolved,
        "unreachable_private": unreachable_private,
        "system_packages": sorted(
            {package for data in system.values() for package in data["packages"]}
        ),
        "glibc_versions": sorted(glibc_versions, key=version_key),
        "glibcxx_versions": sorted(glibcxx_versions, key=version_key),
        "gcc_versions": sorted(gcc_versions, key=version_key),
        "cxxabi_versions": sorted(cxxabi_versions, key=version_key),
        "elfs": elfs,
        "elf_static_archives": elf_static_archives,
        "pkginfo": pkginfo.read_text(errors="replace"),
        "buildinfo_sha256": hashlib.sha256(buildinfo.read_bytes()).hexdigest(),
    }
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    summary_keys = (
        "elf_count",
        "elf_static_archive_count",
        "elf_static_archive_member_count",
        "non_elf_static_archive_count",
        "architectures",
        "interpreters",
        "needed_names",
        "system_packages",
        "glibc_versions",
        "glibcxx_versions",
        "gcc_versions",
        "cxxabi_versions",
        "unresolved_needed",
        "unreachable_private",
    )
    print(json.dumps({key: result[key] for key in summary_keys}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"audit error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
