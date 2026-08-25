import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Lichess Bot: pick a bot difficulty/color/clock in the popup, then hand
// off to a small local HTML page opened in an app-mode browser window,
// which creates the game (via the browser's own fetch(), not curl) and
// redirects straight into the real game on lichess.org.
//
// This plugin used to render its own chessboard in-shell, submitting
// moves via curl. That's gone: curl, run as a child of Quickshell's
// Process, reliably produced requests Lichess treated as bodyless —
// confirmed byte-correct on the wire with curl's own --trace-ascii, so
// the discrepancy was between curl and the server, not anything this
// plugin's code controlled — while the exact same request always worked
// from an interactive shell. See webapp/launch.html for the working
// replacement: a real browser's fetch() is a different network stack
// and process ancestry, and Lichess's API allows the cross-origin
// request (Access-Control-Allow-Origin: *).
BarWidget {
  id: root
  moduleName: "lichess-bot"

  // PersistentProperties only survives a QML hot-reload within the same
  // running Quickshell process — not a full restart (`omarchy restart
  // shell`, a logout, a reboot), which starts a brand new process with
  // none of that in-memory state. Settings need to outlive that, so they
  // live in a real file instead, in the same place Omarchy's own shell
  // keeps its state (~/.local/state/omarchy/*.json).
  readonly property string settingsPath: Quickshell.env("HOME") + "/.local/state/omarchy/lichess-bot-settings.json"

  FileView {
    id: settingsFile
    path: root.settingsPath
    blockLoading: true
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()

    JsonAdapter {
      id: persisted
      property string apiToken: ""
      property int level: 3
      property string color: "random"
      property string clockPreset: "unlimited"
    }
  }

  // The field shows/edits draftToken as you type; persisted.apiToken (the
  // one startGame() actually uses) is only overwritten once that exact
  // draft has been confirmed to work against Lichess — a bad paste never
  // clobbers a previously working saved token.
  property string draftToken: persisted.apiToken

  readonly property string settingsApiToken: draftToken
  readonly property int settingsLevel: persisted.level
  readonly property string settingsColor: persisted.color
  readonly property string settingsClockPreset: persisted.clockPreset
  readonly property string lastError: _lastError

  property string _lastError: ""

  // "" | "checking" | "valid" | "invalid" — tokenStatusDetail holds the
  // username on "valid" or the error message on "invalid". "valid" means
  // draftToken is exactly what's saved in persisted.apiToken right now.
  property string tokenStatus: ""
  property string tokenStatusDetail: ""

  function setApiToken(v) {
    draftToken = v
    tokenStatus = ""
    tokenStatusDetail = ""
    tokenCheckDebounce.restart()
  }

  function setLevel(v) { persisted.level = Math.max(1, Math.min(8, Math.round(v))) }
  function setColor(v) { persisted.color = v }
  function setClockPreset(v) { persisted.clockPreset = v }

  function openTokenPage() {
    var url = "https://lichess.org/account/oauth/token/create" +
      "?description=" + encodeURIComponent("Omarchy Lichess Bot plugin") +
      "&scopes[]=challenge:write"
    Qt.openUrlExternally(url)
  }

  Timer {
    id: tokenCheckDebounce
    interval: 800
    onTriggered: {
      var token = root.draftToken.trim()
      if (token.length === 0) {
        root.tokenStatus = ""
        root.tokenStatusDetail = ""
        return
      }
      root.tokenStatus = "checking"
      root.tokenStatusDetail = ""
      tokenCheckProc.checkedToken = token
      tokenCheckProc.run(token)
    }
  }

  TokenCheck {
    id: tokenCheckProc
    property string checkedToken: ""
    onFinished: function(text) {
      // The draft moved on since this specific check started (more
      // typing/pasting during the round trip) — its result no longer
      // describes what's in the field, so it must not be saved or shown.
      if (checkedToken !== root.draftToken.trim()) return

      var marker = "HTTPSTATUSMARKER:"
      var idx = text.lastIndexOf(marker)
      var status = 0
      var body = text
      if (idx !== -1) {
        status = parseInt(text.substring(idx + marker.length).trim(), 10) || 0
        body = text.substring(0, idx)
      }
      var json = null
      try { json = JSON.parse(body) } catch (e) { /* not JSON */ }

      if (status === 200 && json && json.username) {
        root.tokenStatus = "valid"
        root.tokenStatusDetail = json.username
        persisted.apiToken = checkedToken
      } else {
        root.tokenStatus = "invalid"
        var detail = json && json.error
        root.tokenStatusDetail = detail
          ? (typeof detail === "string" ? detail : JSON.stringify(detail))
          : ("HTTP " + status)
        // persisted.apiToken is deliberately left untouched: a bad paste
        // shouldn't erase a token that was already confirmed working.
      }
    }
  }

  function startGame() {
    if (persisted.apiToken.trim().length === 0) {
      _lastError = "Ajoute ton token API Lichess dans les réglages (clic droit) avant de lancer une partie."
      root.open()
      return
    }
    _lastError = ""

    var parts = [
      "token=" + encodeURIComponent(persisted.apiToken),
      "level=" + encodeURIComponent(persisted.level),
      "color=" + encodeURIComponent(persisted.color)
    ]
    switch (persisted.clockPreset) {
      case "bullet": parts.push("clockLimit=60", "clockIncrement=0"); break
      case "blitz": parts.push("clockLimit=300", "clockIncrement=3"); break
      case "rapid": parts.push("clockLimit=600", "clockIncrement=5"); break
      case "correspondence": parts.push("days=2"); break
      default: break // "unlimited": no clock params
    }

    var pagePath = Qt.resolvedUrl("webapp/launch.html").toString()
    var url = pagePath + "#" + parts.join("&")

    launcherProc.command = ["brave", "--app=" + url]
    launcherProc.running = true
  }

  Process { id: launcherProc }

  Component.onCompleted: {
    if (root.draftToken.trim().length > 0) tokenCheckDebounce.restart()
  }

  // Reverted back to the knight glyph: the real reason it never looked
  // "lit up" was PersistentProperties silently losing the saved token on
  // every full restart (see settingsPath above) — tokenStatus never
  // reached "valid" across a restart, so the pill sat at dimmed's 45%
  // opacity indefinitely, which reads as flat/dark on a bar background
  // regardless of the glyph. If it's still stuck dark after this fix,
  // that theory was wrong and it really is a font/glyph issue.
  readonly property string pillText: "♞"
  readonly property string pillTooltip: "Lichess Bot — clic gauche : nouvelle partie · clic droit : réglages"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "lichess-bot"

    function start(): void { root.startGame() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    tooltipText: root.pillTooltip
    dimmed: root.tokenStatus !== "valid"
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.open()
      else root.startGame()
    }
  }
}
