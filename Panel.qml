import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Game.js" as Game
import "About.js" as About

// The dopewars panel. Laid out like the classic curses screen: a stats box
// (cash, guns, health, bank, debt, bitches, space), the drugs on sale here,
// what's in your trenchcoat, a message area, and the prompt line that changes
// with what the game is asking: "Will you B>uy, S>ell, D>rop, J>et, or
// Q>uit?", a yes/no question, a shop, or a fight.
//
// Every action goes through the shared Service, which saves after each one.
// IPC lives on BarWidget.qml. The About page is AboutView.qml.
Panel {
  id: root
  moduleName: "ninepointlabs.dopewars"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.1)

  // ---------------------------------------------------------------- state --

  readonly property int revision: service ? service.revision : 0
  readonly property var game: service && revision >= 0 ? service.game : null
  readonly property bool hasGame: game !== null && game !== undefined
  readonly property string mode: Game.mode(game)
  readonly property var scores: service ? service.scores : []
  readonly property string shopError: service ? service.shopError : ""

  readonly property var drugsHere: hasGame ? Game.drugsHere(game) : []
  readonly property var carried: hasGame ? Game.carriedDrugs(game) : []
  readonly property var carriedGuns: hasGame ? Game.carriedGuns(game) : []
  readonly property int totalGuns: hasGame ? Game.totalGuns(game.guns) : 0
  readonly property var logTail: hasGame ? game.log.slice(Math.max(0, game.log.length - 6)) : []

  property int selectedDrug: -1
  property bool jetOpen: false
  property bool scoresOpen: false
  property bool confirmQuit: false
  property bool confirmAbandon: false
  property string tradeError: ""
  property bool showAbout: false

  // About page facts read from this plugin's own files, only once it is shown.
  readonly property string pluginDir: {
    var text = String(Qt.resolvedUrl("."))
    if (text.indexOf("file://") === 0) text = decodeURIComponent(text.substring(7))
    return text.length > 1 && text.charAt(text.length - 1) === "/" ? text.substring(0, text.length - 1) : text
  }
  FileView { id: manifestFile; path: root.showAbout ? root.pluginDir + "/manifest.json" : ""; printErrors: false }
  FileView { id: licenseFile; path: root.showAbout ? root.pluginDir + "/LICENSE" : ""; printErrors: false }

  function showAboutPage() {
    showAbout = true
    keyCatcher.forceActiveFocus()
  }

  function hideAbout() {
    showAbout = false
    Qt.callLater(function() {
      if (!root.hasGame) nameField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  readonly property var selected: selectedDrug >= 0 && hasGame ? game.drugs[selectedDrug] : null
  readonly property string selectedName: selectedDrug >= 0 ? Game.DRUGS[selectedDrug].name : ""
  readonly property int maxBuy: selected && selected.price > 0 ? Math.min(Game.canAfford(game, selectedDrug), game.coatSize) : 0

  readonly property string streetPrompt: {
    if (!hasGame) return ""
    var text = "Will you B>uy"
    if (carried.length > 0) text += ", S>ell"
    if (Game.hasWorthless(game)) text += ", D>rop"
    text += ", L>ist, J>et, or Q>uit?"
    return text
  }

  readonly property string fightPrompt: {
    if (!hasGame || !game.fight) return ""
    if (mode === "fightdone") return "Do you D>eal " + Game.NAMES.drugs + "?"
    return "Do you " + (totalGuns > 0 ? "F>ight, " : "S>tand, ") + "R>un, or Q>uit?"
  }

  onModeChanged: {
    if (mode !== "street") { jetOpen = false; confirmQuit = false }
    tradeError = ""
    if (selectedDrug >= 0 && hasGame && game.drugs[selectedDrug].carried === 0 && game.drugs[selectedDrug].price === 0) selectedDrug = -1
  }

  // -------------------------------------------------------------- actions --

  function resetTransient() {
    selectedDrug = -1
    jetOpen = false
    scoresOpen = false
    confirmQuit = false
    confirmAbandon = false
    tradeError = ""
    amountField.text = ""
    loanField.text = ""
    bankField.text = ""
  }

  function startGame() {
    if (!service) return
    service.newGame(nameField.text)
    resetTransient()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function selectDrug(index) {
    selectedDrug = selectedDrug === index ? -1 : index
    tradeError = ""
    amountField.text = ""
    if (selectedDrug >= 0) Qt.callLater(function() { amountField.forceActiveFocus(); amountField.selectAll() })
  }

  function amountValue(field) {
    var n = Math.trunc(Number(String(field.text || "").trim()))
    return isFinite(n) && n > 0 ? n : 0
  }

  function doBuy() {
    if (!service || !selected) return
    if (selected.price === 0) { tradeError = "You can't buy " + selectedName + " here."; return }
    var n = amountValue(amountField)
    if (n === 0) n = maxBuy
    if (n <= 0) { tradeError = maxBuy === 0 && game.coatSize === 0 ? "You don't have enough space to carry any " + selectedName + "!" : "You don't have enough cash to buy any " + selectedName + "!"; return }
    if (n > Game.canAfford(game, selectedDrug)) { tradeError = "You can only afford " + Game.canAfford(game, selectedDrug) + "."; return }
    if (n > game.coatSize) { tradeError = "You can only carry " + game.coatSize + " more."; return }
    service.buyDrug(selectedDrug, n)
    tradeError = ""
    amountField.text = ""
    keyCatcher.forceActiveFocus()
  }

  function doSell() {
    if (!service || !selected) return
    if (selected.carried === 0) { tradeError = "You don't have any " + selectedName + " to sell!"; return }
    var n = amountValue(amountField)
    if (n === 0) n = selected.carried
    if (n > selected.carried) { tradeError = "You have " + selected.carried + "."; return }
    var dropping = selected.price === 0
    service.sellDrug(selectedDrug, n)
    tradeError = ""
    amountField.text = ""
    if (!hasGame || game.drugs[selectedDrug].carried === 0 && dropping) selectedDrug = -1
    keyCatcher.forceActiveFocus()
  }

  function doJet(index) {
    if (!service || !hasGame) return
    if (index === game.isAt) return
    jetOpen = false
    selectedDrug = -1
    tradeError = ""
    service.jet(index)
  }

  function doPay(all) {
    if (!service || !hasGame) return
    var n = all ? Math.min(game.debt, game.cash) : amountValue(loanField)
    if (n <= 0) return
    if (service.payLoan(n)) loanField.text = ""
  }

  function doBank(sign) {
    if (!service || !hasGame) return
    var n = amountValue(bankField)
    if (n === 0) n = sign > 0 ? game.cash : game.bank
    if (n <= 0) return
    if (service.bankMove(sign * n)) bankField.text = ""
  }

  function leaveShop() {
    if (!service) return
    loanField.text = ""
    bankField.text = ""
    service.leaveShop()
    keyCatcher.forceActiveFocus()
  }

  function handleKey(t) {
    if (!service || !hasGame || showAbout) return
    var k = t.toLowerCase()
    if (scoresOpen) { if (k === "l" || k === "q") scoresOpen = false; return }
    switch (mode) {
    case "question":
      if (k === "y") service.answer(true)
      else if (k === "n") service.answer(false)
      break
    case "fight":
      if (k === "f" || k === "s") service.fightAction("F")
      else if (k === "r") service.fightAction("R")
      break
    case "fightdone":
      if (k === "d") service.fightDone()
      break
    case "street":
      if (confirmQuit) {
        if (k === "y") { confirmQuit = false; service.quitGame() }
        else if (k === "n") confirmQuit = false
        return
      }
      if (jetOpen) {
        var n = Number(t)
        if (n >= 1 && n <= Game.LOCATIONS.length) doJet(n - 1)
        else if (k === "q") jetOpen = false
        return
      }
      if (k === "q") confirmQuit = true
      else if (k === "l") scoresOpen = true
      else if (k === "b" || k === "s" || k === "d") {
        if (selectedDrug >= 0) { amountField.forceActiveFocus(); amountField.selectAll() }
        else if (k === "b" && drugsHere.length > 0) selectDrug(drugsHere[0].index)
        else if (carried.length > 0) selectDrug(carried[0].index)
      }
      break
    case "loan":
      if (k === "l") leaveShop()
      else if (k === "p") { loanField.forceActiveFocus(); loanField.selectAll() }
      break
    case "bank":
      if (k === "l") leaveShop()
      else if (k === "d" || k === "w") { bankField.forceActiveFocus(); bankField.selectAll() }
      break
    case "gunshop":
      if (k === "l") leaveShop()
      else if (k === "b" || k === "s") {
        var letter = t.toUpperCase()
        // "B" then a gun letter is the curses flow; here a plain B buys the
        // first gun you can afford, S sells the first you carry.
        for (var gi = 0; gi < Game.GUNS.length; gi++) {
          if (k === "b" && game.cash >= game.gunPrices[gi]) { service.buyGun(gi); break }
          if (k === "s" && game.guns[gi] > 0) { service.sellGun(gi); break }
        }
      }
      break
    case "gameover":
      if (k === "y") { service.abandonGame(); resetTransient(); nameField.forceActiveFocus() }
      break
    }
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  implicitWidth: 1
  implicitHeight: 1

  onOpenedChanged: {
    if (!opened) { showAbout = false; return }
    jetOpen = false
    confirmQuit = false
    confirmAbandon = false
    tradeError = ""
    Qt.callLater(function() {
      if (!root.hasGame) nameField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  // The shell mounts one shared service per plugin, but it can appear a
  // moment after the panels do. Only fall back to a private service if none
  // has shown up after a grace period, and step aside as soon as one does,
  // so two monitors never end up playing two different games.
  Service {
    id: localService
    active: false
  }
  Timer {
    interval: 2500
    running: root.bar !== null && root.sharedService === null && !localService.active
    onTriggered: if (root.sharedService === null) localService.active = true
  }
  onSharedServiceChanged: if (sharedService !== null && localService.active) localService.active = false

  // --------------------------------------------------------------- pieces --

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(root.showAbout ? aboutView.implicitHeight : content.implicitHeight, Style.space(860))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: amountField.activeFocus || nameField.activeFocus || loanField.activeFocus || bankField.activeFocus
      onReturnRequested: {
        if (root.showAbout) return
        if (root.mode === "fightdone" && root.service) root.service.fightDone()
        else if (!root.hasGame) root.startGame()
      }
      // The catcher turns h/j/k/l into moves before textKey sees them, so
      // "l" (L>ist / L>eave) arrives here as a move to the right.
      onMoveRequested: function(dx, dy) { if (dx > 0) root.handleKey("l") }
      onCloseRequested: {
        if (root.showAbout) { root.hideAbout(); return }
        if (root.confirmQuit) { root.confirmQuit = false; return }
        if (root.confirmAbandon) { root.confirmAbandon = false; return }
        if (root.jetOpen) { root.jetOpen = false; return }
        if (root.scoresOpen) { root.scoresOpen = false; return }
        if (root.selectedDrug >= 0) { root.selectedDrug = -1; return }
        if (root.mode === "loan" || root.mode === "bank" || root.mode === "gunshop") { root.leaveShop(); return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleKey(t) }

      AboutView {
        id: aboutView
        objectName: "aboutView"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.showAbout
        foreground: root.foreground
        accent: root.accent
        dim: root.dim
        fontFamily: root.fontFamily
        version: About.manifestVersion(manifestFile.loaded ? manifestFile.text() : "")
        licenseText: licenseFile.loaded ? licenseFile.text() : ""
        onBackRequested: root.hideAbout()
      }

      Column {
        id: content
        anchors.fill: parent
        visible: !root.showAbout
        spacing: Style.space(10)

        // ------------------------------------------------------- header --
        Item {
          width: parent.width
          implicitHeight: Math.max(titleColumn.implicitHeight, headerActions.implicitHeight)

          Column {
            id: titleColumn
            anchors.left: parent.left
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              spacing: Style.space(6)
              Text {
                textFormat: Text.PlainText
                text: "󰐂"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: "D O P E W A R S"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              visible: root.hasGame
              width: parent.width
              textFormat: Text.PlainText
              text: root.hasGame ? Game.statusLine(root.game) + "  ·  " + root.game.name : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              visible: root.hasGame && !root.confirmAbandon
              iconText: "󰔸"
              text: root.scoresOpen ? "Back" : "Scores"
              tooltipText: "High scores (l)"
              selected: root.scoresOpen
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.body
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.scoresOpen = !root.scoresOpen
            }

            Button {
              visible: root.hasGame && !root.game.finished && !root.confirmAbandon
              text: "New game"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.confirmAbandon = true
            }

            Text {
              visible: root.confirmAbandon
              textFormat: Text.PlainText
              text: "Abandon this game?"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            Button {
              visible: root.confirmAbandon
              text: "Yes"
              bordered: true
              foreground: root.urgent
              accent: root.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: { root.confirmAbandon = false; root.service.abandonGame(); root.resetTransient(); nameField.forceActiveFocus() }
            }
            Button {
              visible: root.confirmAbandon
              text: "No"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.confirmAbandon = false
            }

            Button {
              objectName: "aboutButton"
              visible: !root.confirmAbandon
              iconText: "󰋽"
              tooltipText: "About Dopewars"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              iconSize: Style.font.body
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(3)
              onClicked: root.showAboutPage()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ----------------------------------------------------- new game --
        Column {
          visible: !root.hasGame && root.service && root.service.loaded
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: Game.INTRO
            Text {
              required property var modelData
              width: parent.width
              textFormat: Text.PlainText
              text: modelData
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "Hey dude, what's your name?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: nameField
              width: parent.width - startButton.width - parent.spacing
              placeholderText: "Your name"
              text: String(root.setting("playerName", "") || Quickshell.env("USER") || "")
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              Keys.onReturnPressed: root.startGame()
              Keys.onEscapePressed: root.close()
            }

            Button {
              id: startButton
              text: "Start"
              bordered: true
              foreground: root.foreground
              background: Color.popups.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.startGame()
            }
          }

          Column {
            visible: root.scores.length > 0
            width: parent.width
            spacing: Style.space(4)
            PanelSectionHeader { text: "H I G H   S C O R E S"; foreground: root.foreground; fontFamily: root.fontFamily }
            Repeater {
              model: root.scores.slice(0, 5)
              Text {
                required property var modelData
                required property int index
                width: parent.width
                textFormat: Text.PlainText
                text: (index + 1) + ".  " + Game.formatPrice(modelData.money) + "   " + modelData.name + (modelData.dead ? "   (R.I.P.)" : "") + "   " + modelData.date
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }
        }

        // -------------------------------------------------------- stats --
        Grid {
          visible: root.hasGame && !root.scoresOpen
          width: parent.width
          columns: 4
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(6)

          Repeater {
            model: root.hasGame ? [
              { k: "Cash", v: Game.formatPrice(root.game.cash), warn: false },
              { k: "Bank", v: Game.formatPrice(root.game.bank), warn: false },
              { k: "Debt", v: Game.formatPrice(root.game.debt), warn: root.game.debt > 0 },
              { k: "Health", v: String(root.game.health), warn: root.game.health < 40 },
              { k: "Location", v: Game.LOCATIONS[root.game.isAt].name, warn: false },
              { k: "Guns", v: String(root.totalGuns), warn: false },
              { k: "Bitches", v: String(root.game.bitches), warn: false },
              { k: "Space", v: String(root.game.coatSize), warn: root.game.coatSize === 0 }
            ] : []

            Column {
              required property var modelData
              width: (content.width - Style.space(8) * 3) / 4
              spacing: 0
              Text {
                textFormat: Text.PlainText
                text: modelData.k
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.v
                color: modelData.warn ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: modelData.k === "Location" ? Style.font.body : Style.font.subtitle
                font.bold: modelData.k === "Location"
                elide: Text.ElideRight
              }
            }
          }
        }

        PanelSeparator { visible: root.hasGame && !root.scoresOpen; foreground: root.foreground }

        // --------------------------------------------------- high scores --
        Column {
          visible: root.hasGame && root.scoresOpen
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader { text: "H I G H   S C O R E S"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text {
            visible: root.scores.length === 0
            textFormat: Text.PlainText
            text: "No scores yet. Finish a game to get on the table."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.scores
            Row {
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(10)
              readonly property bool mine: root.hasGame && root.game.finished && root.game.scoreRank === index
              Text {
                width: Style.space(24)
                textFormat: Text.PlainText
                text: (index + 1) + "."
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignRight
              }
              Text {
                width: Style.space(120)
                textFormat: Text.PlainText
                text: Game.formatPrice(modelData.money)
                color: parent.mine ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: parent.mine
                horizontalAlignment: Text.AlignRight
              }
              Text {
                width: Style.space(90)
                textFormat: Text.PlainText
                text: modelData.date
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                width: parent.width - Style.space(24 + 120 + 90 + 70) - parent.spacing * 4
                textFormat: Text.PlainText
                text: modelData.name
                color: parent.mine ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
              Text {
                width: Style.space(70)
                textFormat: Text.PlainText
                text: modelData.dead ? "(R.I.P.)" : ""
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        // ------------------------------------------------------- street --
        Row {
          visible: root.hasGame && !root.scoresOpen && (root.mode === "street" || root.mode === "question")
          width: parent.width
          spacing: Style.space(14)

          // Drugs on sale here.
          Column {
            width: (parent.width - parent.spacing) * 0.52
            spacing: Style.space(2)

            PanelSectionHeader { text: "Hey dude, the prices of " + Game.NAMES.drugs + " here are:"; foreground: root.foreground; fontFamily: root.fontFamily }

            Repeater {
              model: root.drugsHere
              Rectangle {
                required property var modelData
                required property int index
                readonly property bool isSelected: root.selectedDrug === modelData.index
                width: parent.width
                height: Style.spacing.popupRowHeight - Style.space(4)
                radius: Style.cornerRadius
                color: isSelected ? Style.selectedFillFor(root.foreground, root.accent) : (rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String.fromCharCode(65 + index) + ".  " + modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Game.formatPrice(modelData.price)
                  color: modelData.carried > 0 ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: root.mode === "street"
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectDrug(modelData.index)
                }
              }
            }

            Text {
              visible: root.drugsHere.length === 0
              textFormat: Text.PlainText
              text: "Nothing on sale here today."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // The trenchcoat.
          Column {
            width: (parent.width - parent.spacing) * 0.48
            spacing: Style.space(2)

            PanelSectionHeader { text: "Trenchcoat"; foreground: root.foreground; fontFamily: root.fontFamily }

            Text {
              visible: root.carried.length === 0 && root.carriedGuns.length === 0
              textFormat: Text.PlainText
              text: "Empty. " + (root.hasGame ? root.game.coatSize : 0) + " space free."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.carried
              Rectangle {
                required property var modelData
                readonly property bool isSelected: root.selectedDrug === modelData.index
                width: parent.width
                height: Style.spacing.popupRowHeight - Style.space(4)
                radius: Style.cornerRadius
                color: isSelected ? Style.selectedFillFor(root.foreground, root.accent) : (coatMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: modelData.price === 0 ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.carried + " @ " + Game.formatPrice(modelData.avg)
                  color: modelData.price === 0 ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: coatMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: root.mode === "street"
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectDrug(modelData.index)
                }
              }
            }

            Repeater {
              model: root.carriedGuns
              Text {
                required property var modelData
                width: parent.width
                leftPadding: Style.space(6)
                textFormat: Text.PlainText
                text: "󰜃  " + modelData.name + "  ×" + modelData.carried
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        // ---------------------------------------------------- trade bar --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "street" && root.selectedDrug >= 0
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              if (!root.selected) return ""
              var parts = [root.selectedName + (root.selected.price > 0 ? " at " + Game.formatPrice(root.selected.price) : " (not sold here)")]
              if (root.selected.carried > 0) parts.push("You have " + root.selected.carried + ".")
              if (root.selected.price > 0) parts.push("You can afford " + Game.canAfford(root.game, root.selectedDrug) + ", and can carry " + root.game.coatSize + ".")
              return parts.join("  ")
            }
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: amountField
              width: Style.space(110)
              placeholderText: "How many?"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              inputMethodHints: Qt.ImhDigitsOnly
              validator: IntValidator { bottom: 0; top: 999999999 }
              // Enter buys when the drug is on sale here, otherwise sells or drops.
              Keys.onReturnPressed: { if (root.selected && root.selected.price > 0) root.doBuy(); else root.doSell() }
              Keys.onEscapePressed: { root.selectedDrug = -1; keyCatcher.forceActiveFocus() }
            }

            Button {
              visible: root.selected && root.selected.price > 0
              text: "Buy" + (root.amountValue(amountField) === 0 && root.maxBuy > 0 ? " " + root.maxBuy : "")
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.doBuy()
            }

            Button {
              visible: root.selected && root.selected.carried > 0
              text: (root.selected && root.selected.price === 0 ? "Drop" : "Sell") + (root.amountValue(amountField) === 0 && root.selected ? " " + root.selected.carried : "")
              bordered: true
              foreground: root.selected && root.selected.price === 0 ? root.urgent : root.foreground
              accent: root.selected && root.selected.price === 0 ? root.urgent : root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.doSell()
            }

            Button {
              text: "Cancel"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: { root.selectedDrug = -1; keyCatcher.forceActiveFocus() }
            }
          }

          Text {
            visible: root.tradeError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.tradeError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
        }

        // ------------------------------------------------- street prompt --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "street"
          width: parent.width
          spacing: Style.space(6)

          PanelSeparator { foreground: root.foreground }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.confirmQuit ? "Are you sure you want to quit?" : (root.jetOpen ? "Where to, dude?" : root.streetPrompt)
            color: root.confirmQuit ? root.urgent : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.Wrap
          }

          Row {
            visible: !root.jetOpen && !root.confirmQuit
            spacing: Style.space(6)

            Button {
              iconText: "󰚬"
              text: "Jet"
              tooltipText: "Travel to another part of the city (a day passes)"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              onClicked: { root.selectedDrug = -1; root.jetOpen = true }
            }

            Button {
              text: "Quit"
              tooltipText: "End the game now and take your score"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              onClicked: root.confirmQuit = true
            }
          }

          Row {
            visible: root.confirmQuit
            spacing: Style.space(6)
            Button {
              text: "Yes, quit"
              bordered: true
              foreground: root.urgent
              accent: root.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              onClicked: { root.confirmQuit = false; root.service.quitGame() }
            }
            Button {
              text: "No"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              onClicked: root.confirmQuit = false
            }
          }

          Flow {
            visible: root.jetOpen
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Game.LOCATIONS
              Button {
                required property var modelData
                required property int index
                readonly property bool here: root.hasGame && root.game.isAt === index
                text: (index + 1) + ". " + modelData.name
                bordered: !here
                enabled: !here
                opacity: here ? 0.45 : 1
                selected: here
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                horizontalPadding: Style.space(10)
                verticalPadding: Style.space(5)
                onClicked: root.doJet(index)
              }
            }

            Button {
              text: "Stay"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              onClicked: root.jetOpen = false
            }
          }
        }

        // ----------------------------------------------------- question --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "question"
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.foreground }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame && root.game.prompt && root.game.prompt.text ? root.game.prompt.text : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.Wrap
          }

          Row {
            spacing: Style.space(6)
            Button {
              text: "Yes"
              tooltipText: "y"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(14)
              verticalPadding: Style.space(5)
              onClicked: root.service.answer(true)
            }
            Button {
              text: "No"
              tooltipText: "n"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(14)
              verticalPadding: Style.space(5)
              onClicked: root.service.answer(false)
            }
          }
        }

        // ---------------------------------------------------- loan shark --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "loan"
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "󱂗  " + Game.NAMES.loanShark; foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.body }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame ? "You owe " + Game.formatPrice(root.game.debt) + ", growing 10% a day. You have " + Game.formatPrice(root.game.cash) + " in cash." : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Text {
            textFormat: Text.PlainText
            text: "How much money do you pay back?"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: loanField
              width: Style.space(130)
              placeholderText: "Amount"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              inputMethodHints: Qt.ImhDigitsOnly
              validator: IntValidator { bottom: 0; top: 999999999 }
              Keys.onReturnPressed: root.doPay(false)
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }
            Button {
              text: "Pay"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.doPay(false)
            }
            Button {
              text: "Pay all"
              bordered: true
              enabled: root.hasGame && root.game.cash > 0
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.doPay(true)
            }
            Button {
              text: "Leave"
              tooltipText: "l"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.leaveShop()
            }
          }
        }

        // ----------------------------------------------------------- bank --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "bank"
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "󰁰  " + Game.NAMES.bank; foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.body }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame ? "Bank balance " + Game.formatPrice(root.game.bank) + ", earning 5% a day. You have " + Game.formatPrice(root.game.cash) + " in cash." : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Text {
            textFormat: Text.PlainText
            text: "Do you want to D>eposit money, W>ithdraw money, or L>eave?"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: bankField
              width: Style.space(130)
              placeholderText: "Amount (blank = all)"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              inputMethodHints: Qt.ImhDigitsOnly
              validator: IntValidator { bottom: 0; top: 999999999 }
              Keys.onReturnPressed: root.doBank(1)
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }
            Button {
              text: "Deposit"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.doBank(1)
            }
            Button {
              text: "Withdraw"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.doBank(-1)
            }
            Button {
              text: "Leave"
              tooltipText: "l"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.leaveShop()
            }
          }
        }

        // ------------------------------------------------------- gun shop --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "gunshop"
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader { text: "󰜃  " + Game.NAMES.gunShop; foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.body }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame ? "Each gun takes 4 space; you can carry " + (root.game.bitches + 2) + " with your " + root.game.bitches + " " + Game.NAMES.bitches + ". Cash " + Game.formatPrice(root.game.cash) + ", space " + root.game.coatSize + "." : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Repeater {
            model: Game.GUNS
            Item {
              required property var modelData
              required property int index
              width: parent.width
              height: Style.spacing.popupRowHeight

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String.fromCharCode(65 + index) + ".  " + modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                anchors.right: gunButtons.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Game.formatPrice(modelData.price) + "   ×" + (root.hasGame ? root.game.guns[index] : 0)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Row {
                id: gunButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Button {
                  text: "Buy"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.service.buyGun(index)
                }
                Button {
                  text: "Sell"
                  bordered: true
                  enabled: root.hasGame && root.game.guns[index] > 0
                  opacity: enabled ? 1 : 0.45
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.service.sellGun(index)
                }
              }
            }
          }

          Text {
            visible: root.shopError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.shopError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Button {
            text: "Leave"
            tooltipText: "l"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(5)
            onClicked: root.leaveShop()
          }
        }

        // Shop errors for the loan shark and bank.
        Text {
          visible: root.hasGame && !root.scoresOpen && (root.mode === "loan" || root.mode === "bank") && root.shopError !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.shopError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ---------------------------------------------------------- fight --
        Column {
          visible: root.hasGame && !root.scoresOpen && (root.mode === "fight" || root.mode === "fightdone") && root.game.fight
          width: parent.width
          spacing: Style.space(8)

          Rectangle {
            width: parent.width
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, root.urgent)
            border.width: Style.spacing.hairline
            border.color: Style.normalBorderFor(root.urgent, root.urgent)
            implicitHeight: fightColumn.implicitHeight + Style.space(20)

            Column {
              id: fightColumn
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  text: "󱅧"
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                  width: parent.width - Style.space(30)
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: {
                      if (!root.hasGame || !root.game.fight) return ""
                      var f = root.game.fight
                      var cop = Game.COPS[f.copIndex - 1]
                      if (f.killed) return f.name + " is dead."
                      if (f.escaped) return "You got away from " + f.name + "."
                      return f.name + (f.deputies > 0 ? " and " + f.deputies + " " + (f.deputies === 1 ? cop.deputy : cop.deputies) : "")
                    }
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Row {
                    width: parent.width
                    spacing: Style.space(10)
                    Text {
                      textFormat: Text.PlainText
                      text: "Cop health " + (root.hasGame && root.game.fight ? root.game.fight.health : 0)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: "Your health " + (root.hasGame ? root.game.health : 0) + "  ·  " + (root.hasGame ? root.game.bitches : 0) + " " + Game.NAMES.bitches + "  ·  " + root.totalGuns + " " + Game.NAMES.guns
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: Style.normalFillFor(root.foreground, root.accent)
                Rectangle {
                  width: parent.width * (root.hasGame && root.game.fight ? Math.max(0, Math.min(100, root.game.fight.health)) / 100 : 0)
                  height: parent.height
                  radius: height / 2
                  color: root.urgent
                }
              }

              Repeater {
                model: root.hasGame && root.game.fight ? root.game.fight.messages : []
                Text {
                  required property var modelData
                  required property int index
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData
                  color: root.hasGame && root.game.fight && index === root.game.fight.messages.length - 1 ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.fightPrompt
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.Wrap
          }

          Row {
            spacing: Style.space(6)

            Button {
              visible: root.mode === "fight"
              iconText: "󰓾"
              text: root.totalGuns > 0 ? "Fight" : "Stand"
              tooltipText: root.totalGuns > 0 ? "f" : "s"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              onClicked: root.service.fightAction("F")
            }
            Button {
              visible: root.mode === "fight"
              iconText: "󰑮"
              text: "Run"
              tooltipText: "r"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              onClicked: root.service.fightAction("R")
            }
            Button {
              visible: root.mode === "fightdone"
              text: "Deal " + Game.NAMES.drugs
              tooltipText: "d or Enter"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(5)
              onClicked: root.service.fightDone()
            }
          }
        }

        // ------------------------------------------------------ game over --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode === "gameover"
          width: parent.width
          spacing: Style.space(8)

          Text {
            visible: root.hasGame && root.game.finishMessage !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame ? root.game.finishMessage : ""
            color: root.hasGame && root.game.dead ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.Wrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame ? "Final score: " + Game.formatPrice(root.game.score) + (root.game.dead ? "   (R.I.P.)" : "") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasGame && root.game.scoreRank >= 0 ? "Congratulations! You made the high scores! (#" + (root.game.scoreRank + 1) + ")" : "You didn't even make the high score table..."
            color: root.hasGame && root.game.scoreRank >= 0 ? root.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Text {
            textFormat: Text.PlainText
            text: "Play again?"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Row {
            spacing: Style.space(6)
            Button {
              text: "Yes"
              tooltipText: "y"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(14)
              verticalPadding: Style.space(5)
              onClicked: { root.service.abandonGame(); root.resetTransient(); nameField.forceActiveFocus() }
            }
            Button {
              text: "Show scores"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              onClicked: root.scoresOpen = true
            }
          }
        }

        // ------------------------------------------------------ messages --
        Column {
          visible: root.hasGame && !root.scoresOpen && root.mode !== "gameover" && root.logTail.length > 0
          width: parent.width
          spacing: Style.space(3)

          PanelSeparator { foreground: root.foreground }

          Repeater {
            model: root.logTail
            Text {
              required property var modelData
              required property int index
              width: parent.width
              textFormat: Text.PlainText
              text: modelData.text
              color: {
                var last = index === root.logTail.length - 1
                if (modelData.kind === "danger") return last ? root.urgent : Qt.darker(root.urgent, 1.3)
                if (modelData.kind === "turn") return last ? root.accent : Qt.darker(root.accent, 1.3)
                if (modelData.kind === "prices") return last ? root.foreground : root.dim
                return last ? root.foreground : root.faint
              }
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: modelData.kind === "prices" && index === root.logTail.length - 1
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }
}
