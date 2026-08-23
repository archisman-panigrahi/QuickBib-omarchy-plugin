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
import json
import re
import sys

KEY_RE = re.compile(r"^@\w+\s*\{\s*([^,\s]+?)\s*,", re.MULTILINE)


def citation_key(bibtex_str):
    """Return the entry key from a BibTeX string, or "" if none is found."""
    match = KEY_RE.search(bibtex_str)
    return match.group(1) if match else ""


def fetch(identifier, timeout):
    """Resolve *identifier* to both citation formats as a result dict."""
    import doi2bib3

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
        print(json.dumps({
            "ok": False,
            "error": "the Python package 'doi2bib3' is not installed "
                     "(on Arch/Omarchy: AUR package python-doi2bib3)",
        }))
        return 1

    try:
        result = fetch(args.identifier, max(1, args.timeout))
    except Exception as exc:
        message = first_line(exc) or exc.__class__.__name__
        print(json.dumps({"ok": False, "error": message}))
        return 1

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
