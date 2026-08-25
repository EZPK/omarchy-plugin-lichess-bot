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
      property string mode: "ai" // "ai" | "casual" | "rated"
      property int level: 3
      property string color: "random"
      property string clockPreset: "unlimited"
    }
  }

  // Populated from GET /api/account (piggybacked on token validation,
  // see TokenCheck below) — the account's real per-speed ratings, used
  // to compute the seek's rating range automatically instead of asking
  // for a manually-typed Elo. Confirmed shape against Perfs.yaml/Perf.yaml:
  // { bullet: {rating, games, ...}, blitz: {...}, rapid: {...}, ... }.
  property var accountPerfs: ({})

  function perfKeyForClockPreset(preset) {
    switch (preset) {
      case "bullet": return "bullet"
      case "blitz": return "blitz"
      case "rapid": return "rapid"
      case "correspondence": return "correspondence"
      default: return "rapid"
    }
  }

  function currentRating() {
    var perf = accountPerfs[perfKeyForClockPreset(persisted.clockPreset)]
    return (perf && typeof perf.rating === "number") ? perf.rating : 1500
  }

  // The field shows/edits draftToken as you type; persisted.apiToken (the
  // one startGame() actually uses) is only overwritten once that exact
  // draft has been confirmed to work against Lichess — a bad paste never
  // clobbers a previously working saved token.
  property string draftToken: persisted.apiToken

  readonly property string settingsApiToken: draftToken
  readonly property string settingsMode: persisted.mode
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

  function setMode(v) {
    var wasHuman = persisted.mode === "casual" || persisted.mode === "rated"
    var isHuman = v === "casual" || v === "rated"
    persisted.mode = v
    // The seek endpoint (mode "casual"/"rated") only accepts Rapid,
    // Classical or Correspondence — confirmed empirically: Bullet and
    // Blitz both fail with "Invalid time control" even in an otherwise
    // minimal request. "Illimitée" isn't valid there either (no untimed
    // option). Landing on a mode-appropriate cadence here means the
    // Cadence dropdown (which hides the now-invalid options per mode)
    // never has to display a stale value that isn't in its own list.
    if (isHuman && !wasHuman) {
      var okForHuman = persisted.clockPreset === "rapid" || persisted.clockPreset === "correspondence"
      if (!okForHuman) persisted.clockPreset = "rapid"
    }
  }

  function setLevel(v) { persisted.level = Math.max(1, Math.min(8, Math.round(v))) }
  function setColor(v) { persisted.color = v }
  function setClockPreset(v) { persisted.clockPreset = v }

  function openTokenPage() {
    // board:play is only needed for "casual"/"rated" modes (POST
    // /api/board/seek + the account event stream), but requesting it
    // unconditionally means switching modes later never requires
    // generating a second token.
    var url = "https://lichess.org/account/oauth/token/create" +
      "?description=" + encodeURIComponent("Omarchy Lichess Bot plugin") +
      "&scopes[]=challenge:write&scopes[]=board:play"
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
        root.accountPerfs = json.perfs || {}
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
      "mode=" + encodeURIComponent(persisted.mode),
      "color=" + encodeURIComponent(persisted.color)
    ]

    if (persisted.mode === "casual" || persisted.mode === "rated") {
      parts.push("rated=" + (persisted.mode === "rated" ? "true" : "false"))
      // Confirmed empirically against the live API: /api/board/seek
      // rejects Bullet and Blitz outright ("Invalid time control", even
      // with an otherwise-minimal request) — only Rapid and
      // Correspondence work. setMode() already steers the persisted
      // cadence away from the other options when switching into these
      // modes, so this default only matters for a value that somehow
      // still isn't one of the two (belt and suspenders).
      var rating = root.currentRating()
      var spread = 150
      parts.push("ratingMin=" + Math.max(0, rating - spread))
      parts.push("ratingMax=" + (rating + spread))
      if (persisted.clockPreset === "correspondence") {
        parts.push("days=2")
      } else {
        parts.push("time=10", "increment=5") // "rapid"
      }
    } else {
      parts.push("level=" + encodeURIComponent(persisted.level))
      switch (persisted.clockPreset) {
        case "bullet": parts.push("clockLimit=60", "clockIncrement=0"); break
        case "blitz": parts.push("clockLimit=300", "clockIncrement=3"); break
        case "rapid": parts.push("clockLimit=600", "clockIncrement=5"); break
        case "correspondence": parts.push("days=2"); break
        default: break // "unlimited": no clock params sent
      }
    }

    var pagePath = Qt.resolvedUrl("webapp/launch.html").toString()
    var url = pagePath + "#" + parts.join("&")

    launcherProc.command = ["brave", "--app=" + url, "--window-size=520,440"]
    launcherProc.running = true
  }

  Process { id: launcherProc }

  Component.onCompleted: {
    if (root.draftToken.trim().length > 0) tokenCheckDebounce.restart()
  }

  // The Unicode chess-knight symbol (♞) was confirmed to render with a
  // fixed white-outline/black-fill baked into the glyph itself, ignoring
  // WidgetButton's text color entirely — a real font issue this time,
  // not the earlier persistence bug. This is a Nerd Font icon instead
  // (Material Design Icons "chess-knight"), same family Pomodoro's
  // glyphs use: plain monochrome outline, so it follows text color and
  // dimmed's opacity correctly. Codepoint confirmed directly against the
  // installed font (JetBrainsMono Nerd Font) via its cmap, not guessed —
  // Nerd Fonts 3.0 relocated this icon block and a guess from an older
  // cheat sheet would have shown a blank box.
  readonly property string pillText: "\u{f0858}" // nf-md-chess_knight
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
