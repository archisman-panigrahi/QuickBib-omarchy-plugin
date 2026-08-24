#!/usr/bin/env python3
# Copyright (c) 2026 Archisman Panigrahi <apandada1ATgmail.com>
#
# GPL-3.0-or-later; same license as the doi2bib3 package this drives.
#
"""Fetch a BibTeX entry and an APS-style \bibitem for one identifier.

The identifier may be a DOI, an arXiv ID, or a paper URL -- anything
doi2bib3's fetch_bibtex() accepts. One network pass: the BibTeX is fetched
once, then formatted locally into a \bibitem via format_bibtex_to_aps_bibitem,
rather than calling fetch_bibitem_aps() and paying for a second resolution.

Prints exactly one JSON object on stdout:
  {"ok": true,  "key": "...", "bibtex": "...", "bibitem": "..."}
  {"ok": false, "error": "..."}
"""

import argparse
from contextlib import contextmanager
import json
import re
import sys
from unittest import mock

KEY_RE = re.compile(r"^@\w+\s*\{\s*([^,\s]+?)\s*,", re.MULTILINE)
MAX_RESPONSE_BYTES = 20 * 1024
MAX_OUTPUT_BYTES = 20 * 1024


def citation_key(bibtex_str):
    """Return the entry key from a BibTeX string, or "" if none is found."""
    match = KEY_RE.search(bibtex_str)
    return match.group(1) if match else ""


class ResponseTooLarge(ValueError):
    """Raised when a remote response exceeds the helper's byte budget."""


@contextmanager
def bounded_doi2bib3_requests():
    """Make doi2bib3 consume responses through a bounded streaming reader."""
    import doi2bib3.backend as backend

    requests_get = backend.requests.get

    def bounded_get(*args, **kwargs):
        kwargs["stream"] = True
        response = requests_get(*args, **kwargs)
        body = bytearray()
        try:
            for chunk in response.iter_content(chunk_size=64 * 1024):
                body.extend(chunk)
                if len(body) > MAX_RESPONSE_BYTES:
                    raise ResponseTooLarge(
                        "remote response exceeds the 20 KiB size limit"
                    )
            response._content = bytes(body)
            response._content_consumed = True
            response.close()
            return response
        except Exception:
            response.close()
            raise

    with mock.patch.object(backend.requests, "get", bounded_get):
        yield


def fetch(identifier, timeout):
    """Resolve *identifier* to both citation formats as a result dict."""
    import doi2bib3

    with bounded_doi2bib3_requests():
        bibtex = doi2bib3.fetch_bibtex(identifier, timeout=timeout)
    if not bibtex.strip():
        raise ValueError("no BibTeX entry found for " + identifier)
    bibitem = doi2bib3.format_bibtex_to_aps_bibitem(bibtex)
    return {
        "ok": True,
        "key": citation_key(bibtex),
        "bibtex": bibtex.strip("\n") + "\n",
        "bibitem": bibitem.strip("\n") + "\n",
    }


def first_line(text):
    """Collapse a possibly multi-line exception string to its first line."""
    lines = [line.strip() for line in str(text).splitlines()]
    return next((line for line in lines if line), "")


def emit_result(result):
    """Print one bounded JSON result, replacing oversized success data."""
    encoded = json.dumps(result).encode("utf-8")
    if len(encoded) + 1 > MAX_OUTPUT_BYTES:
        result = {
            "ok": False,
            "error": "citation output exceeds the size limit",
        }
    print(json.dumps(result))


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Fetch BibTeX and bibitem for a DOI, arXiv ID, or URL."
    )
    parser.add_argument("identifier", help="DOI, arXiv ID, or paper URL")
    parser.add_argument("--timeout", type=int, default=15,
                        help="network timeout in seconds (default: 15)")
    args = parser.parse_args(argv)

    try:
        import doi2bib3  # noqa: F401 -- presence check before any network work
    except ImportError:
        emit_result({
            "ok": False,
            "error": "the Python package 'doi2bib3' is not installed "
                     "(on Arch/Omarchy: AUR package python-doi2bib3)",
        })
        return 1

    try:
        result = fetch(args.identifier, max(1, args.timeout))
    except Exception as exc:
        message = first_line(exc) or exc.__class__.__name__
        emit_result({"ok": False, "error": message[:1024]})
        return 1

    emit_result(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
