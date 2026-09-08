#!/usr/bin/env node
// Plays thousands of random games against the engine and checks the state
// invariants after every single action. Run: node test/play.js [games]
"use strict"

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Game.js"), "utf8").replace(/^\.pragma library\s*/m, "")
const G = {}
vm.runInNewContext(source + "\nthis.__exports = { newGame, sanitizeScores, jet, answer, leaveShop, payLoan, bankMove, buyGun, sellGun, buyDrug, sellDrug, fightAction, fightDone, quitGame, recordScore, mode, validate, drugsHere, carriedDrugs, hasWorthless, canAfford, formatPrice, LOCATIONS, DRUGS, GUNS, E }", G)
const Game = G.__exports

const games = Number(process.argv[2] || 2000)
const stats = { finished: 0, dead: 0, timeUp: 0, paraquat: 0, fights: 0, copsKilled: 0, escaped: 0, doctor: 0, questions: 0, shops: 0, madeTable: 0, maxScore: -Infinity, minScore: Infinity, actions: 0, modes: {} }
const scores = []
let failures = 0

function rnd(n) { return Math.floor(Math.random() * n) }

function check(s, where, seed) {
  const err = Game.validate(s)
  if (err) {
    failures++
    if (failures < 10) console.error(`INVARIANT ${err} after ${where} (seed ${seed}, turn ${s.turn}, mode ${Game.mode(s)})`)
    return false
  }
  return true
}

function playOne(seed) {
  let s = Game.newGame("Tester", seed)
  check(s, "newGame", seed)
  let guard = 0
  let sawFight = false
  while (!s.finished && guard++ < 5000) {
    const m = Game.mode(s)
    stats.modes[m] = (stats.modes[m] || 0) + 1
    stats.actions++
    switch (m) {
    case "street": {
      const r = Math.random()
      const here = Game.drugsHere(s)
      const carried = Game.carriedDrugs(s)
      if (r < 0.35 && here.length) {
        const d = here[rnd(here.length)]
        const max = Math.min(Game.canAfford(s, d.index), s.coatSize)
        if (max > 0) Game.buyDrug(s, d.index, 1 + rnd(max))
        check(s, "buy", seed)
      } else if (r < 0.55 && carried.length) {
        const d = carried[rnd(carried.length)]
        Game.sellDrug(s, d.index, 1 + rnd(d.carried))
        check(s, "sell/drop", seed)
      } else if (r < 0.56) {
        Game.quitGame(s)
      } else {
        const to = rnd(Game.LOCATIONS.length)
        Game.jet(s, to)
        check(s, "jet", seed)
      }
      break
    }
    case "question":
      stats.questions++
      if (s.prompt.code === "weed" && Math.random() < 0.9) Game.answer(s, false)
      else Game.answer(s, Math.random() < 0.6)
      check(s, "answer " + s.prompt, seed)
      break
    case "loan":
      stats.shops++
      Game.payLoan(s, Math.random() < 0.5 ? s.debt : rnd(s.cash + 1))
      check(s, "payLoan", seed)
      Game.leaveShop(s)
      check(s, "leave loan", seed)
      break
    case "bank":
      stats.shops++
      Game.bankMove(s, Math.random() < 0.5 ? rnd(s.cash + 1) : -rnd(s.bank + 1))
      check(s, "bankMove", seed)
      Game.leaveShop(s)
      check(s, "leave bank", seed)
      break
    case "gunshop":
      stats.shops++
      for (let k = 0; k < 3; k++) {
        if (Math.random() < 0.7) Game.buyGun(s, rnd(Game.GUNS.length))
        else Game.sellGun(s, rnd(Game.GUNS.length))
        check(s, "gun trade", seed)
      }
      Game.leaveShop(s)
      check(s, "leave gunshop", seed)
      break
    case "fight":
      if (!sawFight) { stats.fights++; sawFight = true }
      Game.fightAction(s, Math.random() < 0.5 ? "R" : "F")
      check(s, "fightAction", seed)
      if (s.fight && s.fight.over) {
        if (s.fight.killed) stats.copsKilled++
        if (s.fight.escaped) stats.escaped++
        sawFight = false
      }
      break
    case "fightdone":
      sawFight = false
      Game.fightDone(s)
      check(s, "fightDone", seed)
      break
    default:
      throw new Error("unknown mode " + m)
    }
    if (s.prompt && s.prompt.kind === "question" && s.prompt.code === "doctor") stats.doctor++
  }
  if (guard >= 5000) { failures++; console.error("game did not finish, seed " + seed) }
  stats.finished++
  if (s.dead) stats.dead++
  if (s.finishMessage.indexOf("time is up") >= 0) stats.timeUp++
  if (s.finishMessage.indexOf("hallucinated") >= 0) stats.paraquat++
  const rank = Game.recordScore(scores, s)
  if (rank >= 0) stats.madeTable++
  stats.maxScore = Math.max(stats.maxScore, s.score)
  stats.minScore = Math.min(stats.minScore, s.score)
  return s
}

// Deterministic replay: the same seed and the same actions must give the
// same state, otherwise saving and reloading mid-game would drift.
{
  const a = Game.newGame("Replay", 12345)
  const b = Game.newGame("Replay", 12345)
  if (JSON.stringify(a) !== JSON.stringify(b)) { failures++; console.error("newGame is not deterministic for a fixed seed") }
  for (let i = 0; i < 5; i++) {
    Game.jet(a, (a.isAt + 1) % 8); Game.jet(b, (b.isAt + 1) % 8)
    while (a.prompt && a.prompt.kind === "question") { Game.answer(a, false); Game.answer(b, false) }
    while (a.prompt && a.prompt.kind === "fight") { Game.fightAction(a, "R"); Game.fightAction(b, "R") }
    while (a.prompt && a.prompt.kind === "fightdone") { Game.fightDone(a); Game.fightDone(b) }
    while (a.prompt && a.prompt.kind === "question") { Game.answer(a, false); Game.answer(b, false) }
  }
  if (JSON.stringify(a) !== JSON.stringify(b)) { failures++; console.error("replay diverged") }
}

// A game survives a JSON round trip (the save file) at any point, and a
// tampered save is rejected rather than trusted.
{
  const s = Game.newGame("Saver", 777)
  Game.jet(s, 3)
  const copy = JSON.parse(JSON.stringify(s))
  if (Game.validate(copy)) { failures++; console.error("round-tripped state invalid: " + Game.validate(copy)) }
  const tampers = [
    ["cash", "lots"], ["cash", NaN], ["cash", 1e300], ["cash", -5], ["cash", 1.5],
    ["health", 101], ["turn", 0], ["isAt", 99], ["copIndex", 3], ["name", ""], ["name", "x".repeat(41)],
    ["prompt", { kind: "fight" }], ["prompt", { kind: "question", text: 5 }], ["prompt", { kind: "evil" }],
    ["log", new Array(81).fill({ text: "a", kind: "info" })], ["log", [{ text: 7, kind: "info" }]],
    ["guns", [0, 0, 0]], ["drugs", []], ["finished", "yes"], ["date", { d: 32, m: 12, y: 1984 }]
  ]
  for (const [key, value] of tampers) {
    const t = JSON.parse(JSON.stringify(s))
    t[key] = value
    if (!Game.validate(t)) { failures++; console.error("tampered save accepted: " + key + "=" + JSON.stringify(value)) }
  }
  const scores = Game.sanitizeScores([{ money: 5, name: "ok", date: "01-01-2026", dead: false }, { money: "x", name: "bad" }, null, { money: 9, name: 3 }, { money: 7, name: "also", date: "d", dead: "yes" }].concat(new Array(30).fill({ money: 1, name: "n", date: "d" })))
  if (scores.length !== 18 || scores[0].money !== 7 || scores[1].money !== 5 || scores[1].dead !== false) { failures++; console.error("sanitizeScores wrong: " + JSON.stringify(scores.slice(0, 3)) + " len " + scores.length) }
}

const t0 = Date.now()
for (let g = 0; g < games; g++) playOne(1000 + g)
const ms = Date.now() - t0

console.log(JSON.stringify({ games, ms, failures, ...stats, maxScore: Game.formatPrice(stats.maxScore), minScore: Game.formatPrice(stats.minScore), topScore: scores[0] }, null, 1))
process.exit(failures ? 1 : 0)
