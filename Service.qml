import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Non-visual, per the colophon layer split: properties, one Process for the
// fetch helper, clipboard plumbing. Panel.qml binds to these and renders.
Item {
  id: root

  // Injected by Panel.qml; this Item declares no `settings` of its own.
  property var settings: ({})
  property string scriptPath: ""

  property bool loading: false
  property string error: ""
  property string bibtex: ""
  property string bibitem: ""
  property string key: ""
  property int dataVersion: 0

  // Lets onRunningChanged tell a normal exit from a failed spawn (trap #10:
  // Quickshell emits neither exited() nor streamEnded() when the process
  // never starts -- only runningChanged()).
  property bool fetchExited: false
  // One pending slot, not a queue (trap #11: assigning Process.command while
  // running is a silent no-op). The latest request wins.
  property bool pendingRequest: false
  property string pendingIdentifier: ""
  property string lastIdentifier: ""

  // Which section was copied last ("bibtex" / "bibitem"), so the panel can
  // flip that button's label to "copied" until copiedResetTimer fires.
  property string lastCopied: ""

  // Dependency state: "unknown" until probed, then "ok"/"missing". The UI
  // treats anything but "missing" as fine, so a failed probe spawn never
  // blocks the panel.
  property string depStatus: "unknown"
  // True from the click on Install until a recheck proves the import works.
  property bool installing: false

  signal fetched(string identifier)

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return (value === undefined || value === null) ? fallback : value
  }

  readonly property int timeoutSec: setting("timeoutSec", 15)

  function fetch(identifier) {
    var id = String(identifier || "").trim()
    if (id === "") return
    if (fetchProc.running) {
      root.pendingRequest = true
      root.pendingIdentifier = id
      return
    }
    root.startFetch(id)
  }

  function startFetch(id) {
    root.loading = true
    root.error = ""
    root.bibtex = ""
    root.bibitem = ""
    root.key = ""
    root.lastIdentifier = id
    root.fetchExited = false
    // `--` so an identifier starting with "-" cannot be read as a flag.
    fetchProc.command = ["python3", root.scriptPath,
                         "--timeout", String(root.timeoutSec), "--", id]
    fetchProc.running = true
  }

  function copyToClipboard(value, section) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c",
      "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    root.lastCopied = section
    copiedResetTimer.restart()
  }

  // ── Dependency probe & guided install ──
  // The probe is one cheap python spawn at startup. The install is fully
  // click-gated: nothing runs until the user presses the button, and the
  // floating terminal (Omarchy's own launcher, as used by SystemUpdate) is
  // what surfaces yay's sudo password prompt to the user.

  function probeDependency() {
    // Trap #11: never reassign command while running.
    if (depProbe.running) return
    depProbe.command = ["python3", "-c", "import " + Model.DEP_IMPORT_NAME]
    depProbe.running = true
  }

  function installDependency() {
    if (root.installing) return
    root.installing = true
    Quickshell.execDetached(
      ["omarchy-launch-floating-terminal-with-presentation",
       Model.DEP_INSTALL_COMMAND])
    // The launcher detaches immediately; poll the import until it lands.
    depRecheckTimer.restart()
  }

  function handleProbeResult(code, spawned) {
    if (!spawned) {
      // Failed spawn (trap #10): leave depStatus alone -- "unknown" keeps
      // the UI unblocked rather than nagging about a state we could not see.
      return
    }
    root.depStatus = code === 0 ? "ok" : "missing"
    if (root.depStatus === "ok") {
      root.installing = false
      depRecheckTimer.stop()
    }
  }

  function handleOutput(raw) {
    var result = Model.parseResult(raw)
    root.loading = false
    if (!result.ok) {
      root.error = result.error
      return
    }
    root.bibtex = result.bibtex
    root.bibitem = result.bibitem
    root.key = result.key
    root.dataVersion++
    root.fetched(root.lastIdentifier)
  }

  Timer {
    id: copiedResetTimer
    interval: 1500
    onTriggered: root.lastCopied = ""
  }

  Timer {
    // Recheck only while it makes sense: an install in flight. Success stops
    // it via handleProbeResult; the panel closing does not need to stop it --
    // a few extra silent probes are cheaper than state to reset on reopen.
    id: depRecheckTimer
    interval: 2000
    repeat: true
    running: false
    onTriggered: root.probeDependency()
  }

  Process {
    id: depProbe
    property bool probeExited: false
    onExited: function (code, status) {
      probeExited = true
      root.handleProbeResult(code, true)
    }
    onRunningChanged: {
      if (depProbe.running) return
      if (!probeExited) root.handleProbeResult(1, false)
      probeExited = false
    }
  }

  Component.onCompleted: root.probeDependency()

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The helper reports failures as JSON on stdout; stderr content here
        // means it died before its own error handling (e.g. bad interpreter).
        if (text && !root.loading) root.error = text.trim()
      }
    }
    onExited: function (code, status) {
      root.fetchExited = true
      if (code !== 0 && root.error === "" && root.bibtex === "")
        root.error = "lookup failed (exit code " + code + ")"
    }
    onRunningChanged: {
      if (fetchProc.running) return
      // Failed-spawn guard: without this branch a wrong helper path latches
      // loading=true forever (colophon trap #10).
      root.loading = false
      if (!root.fetchExited) root.error = "could not run the fetch helper"
      if (root.pendingRequest) {
        root.pendingRequest = false
        Qt.callLater(function () { root.fetch(root.pendingIdentifier) })
      }
    }
  }
}
