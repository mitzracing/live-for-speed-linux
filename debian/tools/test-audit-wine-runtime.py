#!/usr/bin/env python3
"""Synthetic fail-closed tests for the Wine ABI audit resolver."""

import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("audit-wine-runtime.py")
SPEC = importlib.util.spec_from_file_location("wine_runtime_audit", MODULE_PATH)
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class ResolverTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path("/tmp/synthetic-wine-runtime").resolve()

    def test_resolves_private_provider_per_consumer(self) -> None:
        provider = self.root / "lib/libmixed.so.1"
        needed = {"libmixed.so.1": {"bin/private", "bin/host"}}
        providers = {"libmixed.so.1": {provider}}
        search = {
            "bin/private": [(self.root / "lib").resolve()],
            "bin/host": [(self.root / "other").resolve()],
        }
        system = {"libmixed.so.1": "/usr/lib/libmixed.so.1"}
        with mock.patch.object(AUDIT, "package_owners", return_value=["libmixed1"]):
            private, host, unresolved, unreachable = AUDIT.resolve_dependencies(
                self.root, needed, providers, search, system
            )
        self.assertEqual(private["libmixed.so.1"]["consumers"], ["bin/private"])
        self.assertEqual(host["libmixed.so.1"]["consumers"], ["bin/host"])
        self.assertEqual(unresolved, {})
        self.assertEqual(
            unreachable["libmixed.so.1"]["consumers"], ["bin/host"]
        )

    def test_reports_unresolved_consumer(self) -> None:
        private, host, unresolved, unreachable = AUDIT.resolve_dependencies(
            self.root,
            {"libmissing.so.9": {"bin/wine"}},
            {},
            {"bin/wine": [self.root / "lib"]},
            {},
        )
        self.assertEqual(private, {})
        self.assertEqual(host, {})
        self.assertEqual(unreachable, {})
        self.assertEqual(unresolved, {"libmissing.so.9": ["bin/wine"]})

    def test_resolves_origin_search_path(self) -> None:
        consumer = self.root / "usr/bin/wine"
        self.assertEqual(
            AUDIT.expand_search_path("$ORIGIN/../lib", consumer),
            (self.root / "usr/lib").resolve(),
        )

    def test_rejects_relative_search_path(self) -> None:
        with self.assertRaises(AUDIT.AuditError):
            AUDIT.expand_search_path("relative/lib", self.root / "bin/wine")

    def test_checked_subprocess_failure_is_fatal(self) -> None:
        with self.assertRaises(AUDIT.AuditError):
            AUDIT.run_checked("sh", "-c", "echo failed >&2; exit 7")

    def test_owner_lookup_failure_is_fatal(self) -> None:
        missing = subprocess.CompletedProcess(
            ["dpkg-query"], 1, stdout="", stderr="no path found"
        )
        with mock.patch.object(AUDIT, "run_probe", return_value=missing):
            with self.assertRaises(AUDIT.AuditError):
                AUDIT.package_owners("/usr/lib/libunknown.so.1")


if __name__ == "__main__":
    unittest.main()
