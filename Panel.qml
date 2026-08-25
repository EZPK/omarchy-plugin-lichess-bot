import QtQuick
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
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(mainColumn.implicitHeight)
    focusTarget: keyCatcher

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(12)

        PanelSectionHeader { text: "Défier le bot Lichess"; foreground: root.foreground }

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
          text: "Créer un token (challenge:write)"
          bordered: true
          focusable: true
          foreground: root.foreground
          onClicked: if (root.hostWidget) root.hostWidget.openTokenPage()
        }

        PanelSeparator { foreground: root.foreground }

        NumberField {
          label: "Niveau du bot (1-8)"
          from: 1
          to: 8
          value: root.hostWidget ? root.hostWidget.settingsLevel : 3
          foreground: root.foreground
          onModified: function(v) { if (root.hostWidget) root.hostWidget.setLevel(v) }
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

        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            text: "Cadence"
            color: Qt.darker(root.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          ButtonGroup {
            width: parent.width
            options: [
              { value: "unlimited", label: "Illimitée" },
              { value: "bullet", label: "Bullet 1+0" },
              { value: "blitz", label: "Blitz 5+3" },
              { value: "rapid", label: "Rapide 10+5" },
              { value: "correspondence", label: "Corres. 2j" }
            ]
            value: root.hostWidget ? root.hostWidget.settingsClockPreset : "unlimited"
            foreground: root.foreground
            onChanged: function(v) { if (root.hostWidget) root.hostWidget.setClockPreset(v) }
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

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Ouvre une fenêtre dédiée qui crée la partie puis t'emmène directement dessus sur lichess.org."
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Button {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Nouvelle partie"
          bordered: true
          focusable: true
          foreground: root.foreground
          onClicked: if (root.hostWidget) root.hostWidget.startGame()
        }
      }
    }
  }
}
