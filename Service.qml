import QtQuick
import Quickshell
import Quickshell.Io
import "Game.js" as Game

// The plugin's state layer, one instance per shell: the current game, the
// high score table, and the save file. Every bar widget (one per monitor) and
// every open panel reads this single instance, so a move on one screen shows
// up on all of them and the game is saved exactly once per action.
//
// The save lives in ~/.local/state/omarchy-dopewars/save.json and is written
// after every action, so closing the panel, restarting the shell or rebooting
// never loses a turn.
Item {
  id: root

  property var shell: null
  property var settings: ({})
  // A panel-local instance, built only under a shell without service
  // support, stays inert once a shared one exists.
  property bool active: true

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-dopewars"
  readonly property string savePath: stateDir + "/save.json"

  // ---- state
  property var game: null
  property var scores: []
  property bool loaded: false
  property int revision: 0
  property string shopError: ""
  property bool dirReady: false
  property bool pendingSave: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property bool hasGame: game !== null && game !== undefined
  readonly property string mode: Game.mode(game)
  // True while the game is waiting on the player for something other than a
  // plain street turn: a question, a shop, a fight. The bar chip flags it.
  readonly property bool attention: hasGame && !game.finished && game.prompt !== null

  // ---- persistence -------------------------------------------------------

  Process {
    id: mkdir
    command: ["mkdir", "-p", root.stateDir]
    running: false
    onExited: function(code) {
      root.dirReady = true
      saveFile.reload()
    }
  }

  FileView {
    id: saveFile
    path: root.savePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySave(text())
    onLoadFailed: function(error) { root.applySave("") }
    onSaveFailed: function(error) { console.warn("dopewars: save failed: " + error) }
  }

  function applySave(raw) {
    var data = null
    try { data = raw && raw.trim() !== "" ? JSON.parse(raw) : null } catch (e) { console.warn("dopewars: unreadable save, starting fresh: " + e) }
    if (data && typeof data === "object") {
      scores = Game.sanitizeScores(data.scores)
      var problem = data.game ? Game.validate(data.game) : "no game"
      if (problem === "") game = data.game
      else if (data.game) console.warn("dopewars: dropping corrupt save: " + problem)
    }
    loaded = true
    revision += 1
  }

  function save() {
    if (!loaded) return
    if (!dirReady) { pendingSave = true; return }
    saveFile.setText(JSON.stringify({ version: 1, game: game, scores: scores }, null, 1) + "\n")
  }

  onDirReadyChanged: if (dirReady && pendingSave) { pendingSave = false; save() }

  Component.onCompleted: if (active) mkdir.running = true
  onActiveChanged: if (active && !loaded && !mkdir.running) mkdir.running = true

  // ---- actions -----------------------------------------------------------

  // Every mutation goes through here: the engine works on the object in
  // place, then a fresh reference is assigned so QML bindings re-evaluate,
  // scores are recorded once a game ends, and the save is written.
  function commit() {
    if (game && game.finished && !game.scored) {
      var table = scores.slice()
      Game.recordScore(table, game)
      scores = table
    }
    game = game ? Object.assign({}, game) : null
    revision += 1
    save()
  }

  function act(fn) {
    if (!game) return false
    shopError = ""
    var result = fn(game)
    commit()
    return result
  }

  function newGame(name) {
    var who = String(name || "").trim() || String(setting("playerName", "") || "").trim() || Quickshell.env("USER") || "Dude"
    shopError = ""
    game = Game.newGame(who)
    commit()
  }

  function abandonGame() {
    game = null
    shopError = ""
    revision += 1
    save()
  }

  function jet(to) { return act(function(g) { return Game.jet(g, to) }) }
  function answer(yes) { return act(function(g) { return Game.answer(g, yes) }) }
  function leaveShop() { return act(function(g) { return Game.leaveShop(g) }) }
  function fightAction(action) { return act(function(g) { return Game.fightAction(g, action) }) }
  function fightDone() { return act(function(g) { return Game.fightDone(g) }) }
  function quitGame() { return act(function(g) { return Game.quitGame(g) }) }
  function buyDrug(index, amount) { return act(function(g) { return Game.buyDrug(g, index, amount) }) }
  function sellDrug(index, amount) { return act(function(g) { return Game.sellDrug(g, index, amount) }) }

  function shopCall(fn) {
    if (!game) return false
    var result = fn(game)
    shopError = result && result.error ? result.error : ""
    commit()
    return result && result.ok === true
  }
  function payLoan(amount) { return shopCall(function(g) { return Game.payLoan(g, amount) }) }
  function bankMove(amount) { return shopCall(function(g) { return Game.bankMove(g, amount) }) }
  function buyGun(index) { return shopCall(function(g) { return Game.buyGun(g, index) }) }
  function sellGun(index) { return shopCall(function(g) { return Game.sellGun(g, index) }) }
}
