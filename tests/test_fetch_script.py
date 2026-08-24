#!/usr/bin/env python3
"""Unit tests for scripts/quickbib_fetch.py.

doi2bib3 is stubbed in sys.modules, so no test touches the network.
Run: python3 -m unittest discover -s tests
"""

import json
import sys
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import quickbib_fetch  # noqa: E402

BIBTEX = """@article{doe2024,
  title = {Test Paper},
  author = {Doe, Jane},
  journal = {Phys. Rev. A},
  year = {2024}
}
"""
BIBITEM = "\\bibitem{doe2024}\nJ. Doe, Test Paper (2024).\n"


def make_fake_doi(fetch_result=None, fetch_exc=None):
    fake = mock.MagicMock()
    if fetch_exc is not None:
        fake.fetch_bibtex.side_effect = fetch_exc
    else:
        fake.fetch_bibtex.return_value = BIBTEX if fetch_result is None \
            else fetch_result
    fake.format_bibtex_to_aps_bibitem.return_value = BIBITEM
    return fake


def install_fake_doi(fetch_result=None, fetch_exc=None):
    backend = mock.MagicMock()
    backend.requests = mock.MagicMock()
    return mock.patch.dict(
        sys.modules,
        {
            "doi2bib3": make_fake_doi(fetch_result, fetch_exc),
            "doi2bib3.backend": backend,
        })


class CitationKeyTest(unittest.TestCase):
    def test_extracts_the_key(self):
        self.assertEqual(quickbib_fetch.citation_key(BIBTEX), "doe2024")

    def test_tolerates_spaces(self):
        self.assertEqual(
            quickbib_fetch.citation_key("@article { mykey ,\ntitle={x}}"),
            "mykey")

    def test_missing_key_is_empty(self):
        self.assertEqual(quickbib_fetch.citation_key("not bibtex"), "")


class FetchTest(unittest.TestCase):
    def test_returns_both_formats_and_key(self):
        with install_fake_doi():
            result = quickbib_fetch.fetch("10.1234/x", 15)
        self.assertTrue(result["ok"])
        self.assertEqual(result["bibtex"], BIBTEX.strip("\n") + "\n")
        self.assertEqual(result["bibitem"], BIBITEM.strip("\n") + "\n")
        self.assertEqual(result["key"], "doe2024")

    def test_empty_bibtex_raises(self):
        with install_fake_doi(fetch_result=""):
            with self.assertRaises(ValueError):
                quickbib_fetch.fetch("10.1234/x", 15)

    def test_timeout_is_forwarded(self):
        fake = make_fake_doi()
        backend = mock.MagicMock()
        backend.requests = mock.MagicMock()
        with mock.patch.dict(sys.modules, {
            "doi2bib3": fake,
            "doi2bib3.backend": backend,
        }):
            quickbib_fetch.fetch("10.1234/x", 42)
        fake.fetch_bibtex.assert_called_once_with("10.1234/x", timeout=42)

    def test_response_reader_rejects_oversized_body(self):
        response = mock.MagicMock()
        response.iter_content.return_value = [
            b"x" * (quickbib_fetch.MAX_RESPONSE_BYTES + 1)
        ]
        requests = mock.MagicMock()
        requests.get.return_value = response
        backend = mock.MagicMock()
        backend.requests = requests
        with mock.patch.dict(sys.modules, {"doi2bib3.backend": backend}):
            with self.assertRaises(quickbib_fetch.ResponseTooLarge):
                with quickbib_fetch.bounded_doi2bib3_requests():
                    requests.get("https://example.test")
        response.close.assert_called_once_with()


class MainTest(unittest.TestCase):
    def run_main(self, argv):
        stdout = io_capture()
        with mock.patch.object(sys, "stdout", stdout):
            code = quickbib_fetch.main(argv)
        return code, stdout.getvalue()

    def test_success_prints_one_json_object(self):
        with install_fake_doi():
            code, out = self.run_main(["10.1234/x"])
        self.assertEqual(code, 0)
        parsed = json.loads(out)
        self.assertTrue(parsed["ok"])

    def test_failure_prints_json_error_and_exits_nonzero(self):
        with install_fake_doi(fetch_exc=RuntimeError("boom\nsecond line")):
            code, out = self.run_main(["10.1234/x"])
        self.assertEqual(code, 1)
        parsed = json.loads(out)
        self.assertFalse(parsed["ok"])
        self.assertEqual(parsed["error"], "boom")

    def test_missing_package_reports_install_hint(self):
        with mock.patch.dict(sys.modules, {"doi2bib3": None}):
            builtins = sys.modules["builtins"]
            real_import = builtins.__import__

            def no_doi(name, *a, **k):
                if name == "doi2bib3":
                    raise ImportError(name)
                return real_import(name, *a, **k)

            with mock.patch.object(builtins, "__import__", side_effect=no_doi):
                code, out = self.run_main(["10.1234/x"])
        self.assertEqual(code, 1)
        error = json.loads(out)["error"]
        self.assertIn("doi2bib3", error)
        self.assertIn("python-doi2bib3", error)

    def test_oversized_output_is_replaced_with_bounded_error(self):
        oversized = dict(
            ok=True,
            key="key",
            bibtex="x" * quickbib_fetch.MAX_OUTPUT_BYTES,
            bibitem="",
        )
        stdout = io_capture()
        with mock.patch.object(sys, "stdout", stdout):
            quickbib_fetch.emit_result(oversized)
        self.assertLessEqual(
            len(stdout.getvalue().encode("utf-8")),
            quickbib_fetch.MAX_OUTPUT_BYTES,
        )
        self.assertFalse(json.loads(stdout.getvalue())["ok"])


def io_capture():
    class Capture:
        def __init__(self):
            self.parts = []

        def write(self, text):
            self.parts.append(text)

        def getvalue(self):
            return "".join(self.parts)
    return Capture()


if __name__ == "__main__":
    unittest.main()
