// Pure helpers for QuickBib. Same QML-safe JS rules as ssandys.colophon's
// Model.js: top-level var/function declarations only -- no arrow functions,
// let/const, template literals, spread, .includes(), or .endsWith().
var BAR_GLYPH = "\uF02D"

var REPORT_ISSUES_URL =
  "https://github.com/archisman-panigrahi/QuickBib-omarchy-plugin"

// The dependency the fetch helper needs, and how this plugin installs it.
// Both are shown to the user before anything runs -- the install itself is
// click-gated (Omarchy never executes plugin code at install time, so there
// is no silent path).
var DEP_PACKAGE = "python-doi2bib3"
var DEP_IMPORT_NAME = "doi2bib3"
var DEP_INSTALL_COMMAND = "omarchy-pkg-aur-add python-doi2bib3"

// Parse the fetch helper's stdout into a result object. Never throws: any
// surprise becomes {"ok": false, "error": ...} so the panel can show it.
function parseResult(raw) {
  try {
    var value = JSON.parse(raw)
  } catch (err) {
    return { ok: false, error: "unreadable helper output" }
  }
  if (!value || typeof value !== "object")
    return { ok: false, error: "unexpected helper output" }
  if (value.ok !== true)
    return { ok: false, error: String(value.error || "lookup failed") }
  return {
    ok: true,
    key: String(value.key || ""),
    bibtex: String(value.bibtex || ""),
    bibitem: String(value.bibitem || "")
  }
}
