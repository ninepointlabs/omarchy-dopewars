import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar chip: a pill glyph plus, while a game is on, the day and your cash.
// The glyph brightens when the game is waiting on you (a cop, a question, a
// shop) so a half-finished turn is never forgotten. Click to open the game.
BarWidget {
  id: root
  moduleName: "ninepointlabs.dopewars"

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property int revision: service ? service.revision : 0
  readonly property var game: service && revision >= 0 ? service.game : null
  readonly property bool hasGame: game !== null && game !== undefined
  readonly property bool attention: service ? service.attention === true : false
  readonly property bool showStatus: setting("showStatus", true) === true

  readonly property string labelText: {
    if (!hasGame) return ""
    if (game.finished) return "Game over"
    return "Day " + game.turn + " · " + formatPrice(game.cash)
  }

  function formatPrice(n) {
    n = Math.trunc(Number(n) || 0)
    var neg = n < 0
    var digits = String(Math.abs(n))
    var out = ""
    for (var i = 0; i < digits.length; i++) {
      var fromEnd = digits.length - i
      out += digits.charAt(i)
      if (fromEnd > 1 && (fromEnd - 1) % 3 === 0) out += ","
    }
    return "$" + (neg ? "-" : "") + out
  }

  readonly property color chipColor: {
    if (!bar) return Color.foreground
    if (attention) return Color.accent
    if (hasGame && !game.finished) return bar.barForeground
    return Qt.darker(bar.barForeground, 1.5)
  }

  // ---- Panel popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function anyOpened() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].opened === true) return true
    return false
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

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
    target: "ninepointlabs.dopewars"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function isOpen(): string { return root.anyOpened() ? "true" : "false" }
    function status(): string { return root.service && root.service.game ? JSON.stringify({ mode: root.service.mode, turn: root.service.game.turn, cash: root.service.game.cash, at: root.service.game.isAt }) : "{}" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(chipRow.implicitWidth + Style.spaceReal(horizontalMargin) * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: root.labelText !== "" && root.showStatus && !root.vertical ? 7 : 6
    tooltipText: root.hasGame ? "Dopewars · " + root.labelText + (root.attention ? " · waiting on you" : "") : "Dopewars"

    onPressed: function(b) { root.togglePanel() }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      OpticalGlyph {
        width: Style.bar.iconCanvas + Style.space(2)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        text: "󰐂"
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        color: root.chipColor
      }

      Text {
        visible: root.showStatus && !root.vertical && root.labelText !== ""
        textFormat: Text.PlainText
        text: root.labelText
        color: root.chipColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
