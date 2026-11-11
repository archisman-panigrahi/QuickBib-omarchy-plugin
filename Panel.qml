import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "archisman-panigrahi.quickbib"
  ipcTarget: "archisman-panigrahi.quickbib"

  // \uXXXX escape, never the literal glyph (colophon trap #14: PUA characters
  // do not survive every editing path).
  readonly property string barIcon: Model.BAR_GLYPH
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  // Applied locally first so the checkbox redraws on the click itself; the
  // shell.json write comes back through the bar as the same value (same
  // pattern as the clock panel). With no writable entry it stays a
  // session-only preference rather than doing nothing.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell &&
        typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setMbox(enabled) {
    if (service.mbox === enabled) return
    persistSettings({ mbox: enabled })
    // Re-run the last lookup so the shown output matches the ticked state.
    // A fetch in flight queues this as its pending request instead (trap
    // #11), so it still lands with the new flag. Only refresh when results
    // are on screen -- an error or empty panel is left for the next fetch.
    if (service.bibtex !== "")
      Qt.callLater(function () { service.fetch(service.lastIdentifier) })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: service
    settings: root.settings
    scriptPath: root.pathFromUrl(Qt.resolvedUrl("scripts/quickbib_fetch.py"))
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    // Dim while the fetch dependency is missing, so the icon itself hints
    // that something is off before the panel is ever opened.
    foreground: service.depStatus === "missing" ? root.dim : root.barForeground
    tooltipText: service.depStatus === "missing"
      ? "QuickBib -- missing python-doi2bib3 (open to install)"
      : "QuickBib -- BibTeX & bibitem from DOI / arXiv / URL"
    onPressed: function (which) {
      if (root.opened) root.close()
      else root.open()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    ColumnLayout {
      id: contentColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(8)

      // ── Header ──
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: root.barIcon + "  QuickBib"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
        }

        Text {
          visible: service.key !== ""
          text: service.key
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
          Layout.maximumWidth: panel.contentWidth * 0.45
        }
      }

      PanelSeparator { Layout.fillWidth: true; foreground: root.fg }

      // ── Dependency notice ──
      // Fully transparent about what the button will run before it runs:
      // Omarchy never executes plugin code at install time, so this is the
      // one sanctioned moment a plugin can offer to install anything.
      ColumnLayout {
        Layout.fillWidth: true
        visible: service.depStatus === "missing"
        spacing: Style.space(4)

        Text {
          text: "QuickBib needs the Python package " + Model.DEP_IMPORT_NAME +
                " to fetch citations, and it is missing from this system."
          color: "#eab308"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }

        Text {
          text: "Clicking Install opens a floating terminal that runs " +
                "Omarchy's own package helper:\n" +
                Model.DEP_INSTALL_COMMAND +
                "\n(installs AUR package " + Model.DEP_PACKAGE +
                "; you may be asked for your sudo password)."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }

        Button {
          text: service.installing
            ? "installer opened — finish in the terminal window…"
            : "Install " + Model.DEP_PACKAGE
          foreground: service.installing ? root.dim : Color.accent
          tooltipText: "Runs: " + Model.DEP_INSTALL_COMMAND +
                       "  (in a floating terminal)"
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(6)
          verticalPadding: Style.space(2)
          enabled: !service.installing
          opacity: enabled ? 1.0 : 0.6
          onClicked: service.installDependency()
        }
      }

      // ── Input ──
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        TextField {
          id: identifierInput
          Layout.fillWidth: true
          placeholderText: "DOI, arXiv ID, or paper URL"
          foreground: root.fg
          font.family: root.fontFamily
          enabled: !service.loading
          opacity: enabled ? 1.0 : 0.6
          onAccepted: service.fetch(text)
          Keys.onEscapePressed: root.close()
        }

        Button {
          text: service.loading ? "…" : "fetch"
          foreground: Color.accent
          tooltipText: "Fetch BibTeX and bibitem"
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(6)
          verticalPadding: Style.space(2)
          enabled: identifierInput.text.trim() !== "" && !service.loading
          opacity: enabled ? 1.0 : 0.4
          onClicked: service.fetch(identifierInput.text)
        }
      }

      // ── mbox option ──
      // Checkmark row for doi2bib3's --mbox. Clicking flips the persisted
      // setting; the next fetch (including one still pending) picks it up.
      Item {
        Layout.fillWidth: true
        implicitHeight: Math.max(mboxRow.implicitHeight, Style.space(16))

        RowLayout {
          id: mboxRow
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(6)

          // Checkbox square with a tick, same visual language as the
          // shell kit's MultiSelect checkboxes.
          BorderSurface {
            id: mboxBox
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Style.space(16)
            implicitHeight: Style.space(16)
            radius: Math.max(2, Style.cornerRadius / 2)
            color: service.mbox
              ? Style.selectedFillFor(root.fg, Color.accent)
              : "transparent"
            borderSpec: service.mbox
              ? Border.controlSpec("selected", root.fg, Color.accent)
              : Border.controlSpec("normal", root.fg, Color.accent)

            Text {
              anchors.centerIn: parent
              visible: service.mbox
              text: "\u2713"
              color: Style.selectedStateColor(root.fg, Color.accent)
              font.family: root.fontFamily
              font.pixelSize: Math.round(mboxBox.height * 0.85)
              font.bold: true
            }
          }

          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: "Prevent line breaking in author names"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.setMbox(!service.mbox)
        }
      }

      // ── Status / error strip ──
      Text {
        visible: service.error !== ""
        text: service.error
        color: "#ef4444"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      Text {
        visible: service.loading
        text: "fetching " + service.lastIdentifier + " …"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
        elide: Text.ElideMiddle
      }

      Text {
        visible: !service.loading && service.error === "" &&
                 service.bibtex === ""
        text: "Enter a DOI, arXiv ID (e.g. 2401.12345), or article URL."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      // ── BibTeX ──
      RowLayout {
        Layout.fillWidth: true
        visible: service.bibtex !== ""
        spacing: Style.space(6)

        Text {
          text: "BIBTEX"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          Layout.fillWidth: true
        }

        Button {
          text: service.lastCopied === "bibtex" ? "copied" : "copy"
          foreground: service.lastCopied === "bibtex" ? "#22c55e" : root.fg
          tooltipText: "Copy the BibTeX entry to the clipboard"
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(6)
          verticalPadding: Style.space(2)
          enabled: service.bibtex !== ""
          onClicked: service.copyToClipboard(service.bibtex, "bibtex")
        }
      }

      ScrollView {
        id: bibtexScroll
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(bibtexText.implicitHeight,
                                         Style.space(170))
        clip: true
        visible: service.bibtex !== ""
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        // Read-only TextArea, not Text: Text cannot be user-selected at all.
        // selectByMouse gives drag + double-click selection; readOnly keeps
        // Ctrl+C (copy) working while blocking edits.
        TextArea {
          id: bibtexText
          width: bibtexScroll.availableWidth
          text: service.bibtex
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.WrapAnywhere
          readOnly: true
          selectByMouse: true
          selectionColor: Style.selectionFillFor(root.fg, Color.accent)
          selectedTextColor: root.fg
          background: null
        }
      }

      // ── Bibitem ──
      RowLayout {
        Layout.fillWidth: true
        visible: service.bibitem !== ""
        spacing: Style.space(6)

        Text {
          text: "BIBITEM"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          Layout.fillWidth: true
        }

        Button {
          text: service.lastCopied === "bibitem" ? "copied" : "copy"
          foreground: service.lastCopied === "bibitem" ? "#22c55e" : root.fg
          tooltipText: "Copy the \\bibitem entry to the clipboard"
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(6)
          verticalPadding: Style.space(2)
          enabled: service.bibitem !== ""
          onClicked: service.copyToClipboard(service.bibitem, "bibitem")
        }
      }

      ScrollView {
        id: bibitemScroll
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(bibitemText.implicitHeight,
                                         Style.space(120))
        clip: true
        visible: service.bibitem !== ""
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        // Read-only TextArea, not Text: Text cannot be user-selected at all.
        TextArea {
          id: bibitemText
          width: bibitemScroll.availableWidth
          text: service.bibitem
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.WrapAnywhere
          readOnly: true
          selectByMouse: true
          selectionColor: Style.selectionFillFor(root.fg, Color.accent)
          selectedTextColor: root.fg
          background: null
        }
      }

      PanelSeparator { Layout.fillWidth: true; foreground: root.fg }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "enter to fetch · esc to close"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Item {
        Layout.fillWidth: true
        implicitHeight: reportLink.implicitHeight

        Text {
          id: reportLink
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Report Issues"
          color: reportHover.hovered ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: reportHover.hovered

          MouseArea {
            id: reportHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(Model.REPORT_ISSUES_URL)
          }
        }
      }
    }
  }

  onOpenedChanged: {
    if (opened) {
      identifierInput.forceActiveFocus()
      identifierInput.selectAll()
    }
  }

  // Local-testing IPC, separate target from the base Panel's open/close/
  // toggle handler. Lets you fake the dependency state without uninstalling
  // python-doi2bib3:
  //   omarchy-shell archisman-panigrahi.quickbib.dev simulateMissingDep
  //   omarchy-shell archisman-panigrahi.quickbib.dev simulateDepOk
  IpcHandler {
    target: "archisman-panigrahi.quickbib.dev"

    function simulateMissingDep(): void { service.debugSetDep("missing") }
    function simulateDepOk(): void { service.debugSetDep("ok") }
  }
}
