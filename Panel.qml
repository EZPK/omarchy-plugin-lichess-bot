import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "lichess-bot"

  property var anchorItem: null
  property var hostWidget: null

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(340))
    // Capped: this panel's content has grown past what fits on shorter
    // screens (three modes, per-mode hint text, rating line...) with no
    // way to reach what's cut off — fittedContentHeight() only clamps to
    // the screen's available height, it doesn't add scrolling on its
    // own. The Flickable below (same pattern as the built-in
    // tailscale/bluetooth/dropbox panels) makes the excess reachable.
    contentHeight: popup.fittedContentHeight(mainColumn.implicitHeight, Style.space(480))
    focusTarget: keyCatcher

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: mainColumn
        width: panelFlick.width
        spacing: Style.space(12)

        PanelSectionHeader { text: "Réglages — Lichess Bot"; foreground: root.foreground }

        TextField {
          width: parent.width
          password: true
          placeholderText: "Token API Lichess"
          text: root.hostWidget ? root.hostWidget.settingsApiToken : ""
          foreground: root.foreground
          onTextChanged: if (root.hostWidget) root.hostWidget.setApiToken(text)
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.hostWidget && root.hostWidget.tokenStatus !== ""
          text: {
            if (!root.hostWidget) return ""
            switch (root.hostWidget.tokenStatus) {
              case "checking": return "Vérification du token…"
              case "valid": return "✓ Connecté en tant que " + root.hostWidget.tokenStatusDetail
              case "invalid": return "✗ Token invalide : " + root.hostWidget.tokenStatusDetail
              default: return ""
            }
          }
          color: root.hostWidget && root.hostWidget.tokenStatus === "invalid"
            ? Color.urgent
            : Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Button {
          // Was "Créer un token (challenge:write + board:play)" — a
          // Button auto-sizes to its label with no wrapping, so a long
          // enough one overflows the panel's width outright. The scopes
          // are still documented, just in README.md instead of here.
          text: "Créer un token"
          bordered: true
          focusable: true
          foreground: root.foreground
          onClicked: if (root.hostWidget) root.hostWidget.openTokenPage()
        }

        PanelSeparator { foreground: root.foreground }

        Dropdown {
          width: parent.width
          label: "Adversaire"
          // A 3-way ButtonGroup here overflowed the popup — same issue
          // Cadence had with 5 options — since ButtonGroup lays chips out
          // in a single non-wrapping row. Dropdown doesn't have that
          // problem regardless of how many/long the options are.
          options: [
            { value: "ai", label: "Bot Lichess" },
            { value: "casual", label: "Joueur, non classé" },
            { value: "rated", label: "Joueur, classé" }
          ]
          value: root.hostWidget ? root.hostWidget.settingsMode : "ai"
          foreground: root.foreground
          background: root.bar ? root.bar.background : Color.background
          onChanged: function(v) { if (root.hostWidget) root.hostWidget.setMode(v) }
        }

        NumberField {
          visible: root.hostWidget && root.hostWidget.settingsMode === "ai"
          label: "Niveau du bot (1-8)"
          from: 1
          to: 8
          value: root.hostWidget ? root.hostWidget.settingsLevel : 3
          foreground: root.foreground
          onModified: function(v) { if (root.hostWidget) root.hostWidget.setLevel(v) }
        }

        Text {
          // One combined line instead of three separate paragraphs
          // (rating, rated-mode note, casual-mode note) — this panel's
          // total height was pushing Cadence low enough that its own
          // dropdown list, which only opens downward, had nowhere left
          // to open into. Scope requirement is in README.md.
          visible: root.hostWidget && root.hostWidget.settingsMode !== "ai"
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.hostWidget
            ? "Classement " + (root.hostWidget.settingsClockPreset === "correspondence" ? "correspondance" : "rapide") +
              " : " + root.hostWidget.currentRating() + " (±150)" +
              (root.hostWidget.settingsMode === "rated" ? " — classée, affecte ton classement" : " — non classée")
            : ""
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Dropdown {
          // Moved ahead of Couleur (was after it): this is the one
          // control in the panel whose own popup list needs room to open
          // downward, so it gets first claim on whatever vertical space
          // is left in the card rather than sitting lowest and most
          // likely to have nowhere left to open into.
          width: parent.width
          label: "Cadence"
          // Confirmed empirically against the live API: POST
          // /api/board/seek (modes "casual"/"rated") rejects Bullet and
          // Blitz outright ("Invalid time control", even in an
          // otherwise-minimal request) and has no untimed option either
          // — only Rapide and Correspondance work. The AI endpoint (mode
          // "ai") has no such restriction.
          options: (root.hostWidget && root.hostWidget.settingsMode !== "ai")
            ? [
                { value: "rapid", label: "Rapide 10+5" },
                { value: "correspondence", label: "Correspondance 2j" }
              ]
            : [
                { value: "unlimited", label: "Illimitée" },
                { value: "bullet", label: "Bullet 1+0" },
                { value: "blitz", label: "Blitz 5+3" },
                { value: "rapid", label: "Rapide 10+5" },
                { value: "correspondence", label: "Correspondance 2j" }
              ]
          value: root.hostWidget ? root.hostWidget.settingsClockPreset : "unlimited"
          foreground: root.foreground
          background: root.bar ? root.bar.background : Color.background
          onChanged: function(v) { if (root.hostWidget) root.hostWidget.setClockPreset(v) }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            text: "Couleur"
            color: Qt.darker(root.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          ButtonGroup {
            width: parent.width
            options: [
              { value: "random", label: "Aléatoire" },
              { value: "white", label: "Blancs" },
              { value: "black", label: "Noirs" }
            ]
            value: root.hostWidget ? root.hostWidget.settingsColor : "random"
            foreground: root.foreground
            onChanged: function(v) { if (root.hostWidget) root.hostWidget.setColor(v) }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Text {
          visible: root.hostWidget && root.hostWidget.lastError !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.hostWidget ? root.hostWidget.lastError : ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
      }
    }
  }
}
