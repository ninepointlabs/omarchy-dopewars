.pragma library

// dopewars, the single-player game, as a pure JavaScript engine.
//
// This is a transcription of the server-side game logic of dopewars 1.6.2
// (Ben Webb, GPL-2.0), itself based on John E. Dell's 1984 "Drug Wars".
// Every number, probability and message here comes from the C source
// (dopewars.c defaults, serverside.c logic, message.c fight strings). The
// event state machine (E_SUBWAY .. E_ARRIVE) is kept as-is so the sequence of
// offers, cops, shops and price rolls between turns matches the original.
//
// The engine is side-effect free: every function takes the game state object,
// mutates it in place, and returns it. The QML layer owns persistence and
// rendering. All randomness comes from a seeded generator stored in the state,
// so a game can be replayed and tested from Node (see test/).

// ---------------------------------------------------------------- data ------

var NUM_TURNS = 31
var START_CASH = 2000
var START_DEBT = 5500
var DEBT_INTEREST = 10
var BANK_INTEREST = 5
var LOAN_SHARK_LOC = 1     // 1-based location indexes, as in the config file
var BANK_LOC = 1
var GUN_SHOP_LOC = 2
var ROUGH_PUB_LOC = 2
var BITCH_MIN_PRICE = 50000
var BITCH_MAX_PRICE = 150000
var CHEAP_DIVIDE = 4
var EXPENSIVE_MULTIPLY = 4
var PLAYER_ARMOR = 100
var BITCH_ARMOR = 50
var NUM_HISCORE = 18
var LOG_LIMIT = 80

var NAMES = {
  bitch: "bitch", bitches: "bitches",
  gun: "gun", guns: "guns",
  drug: "drug", drugs: "drugs",
  loanShark: "the Loan Shark", bank: "the Bank",
  gunShop: "Dan's House of Guns", pub: "the pub"
}

var LOCATIONS = [
  { name: "Bronx",         police: 10, minDrug: 7, maxDrug: 12 },
  { name: "Ghetto",        police: 5,  minDrug: 8, maxDrug: 12 },
  { name: "Central Park",  police: 15, minDrug: 6, maxDrug: 12 },
  { name: "Manhattan",     police: 90, minDrug: 4, maxDrug: 10 },
  { name: "Coney Island",  police: 20, minDrug: 6, maxDrug: 12 },
  { name: "Brooklyn",      police: 70, minDrug: 4, maxDrug: 11 },
  { name: "Queens",        police: 50, minDrug: 6, maxDrug: 12 },
  { name: "Staten Island", police: 20, minDrug: 6, maxDrug: 12 }
]

var DRUGS = [
  { name: "Acid",    min: 1000,  max: 4400,  cheap: true,  expensive: false, cheapStr: "The market is flooded with cheap home-made acid!" },
  { name: "Cocaine", min: 15000, max: 29000, cheap: false, expensive: true,  cheapStr: "" },
  { name: "Hashish", min: 480,   max: 1280,  cheap: true,  expensive: false, cheapStr: "The Marrakesh Express has arrived!" },
  { name: "Heroin",  min: 5500,  max: 13000, cheap: false, expensive: true,  cheapStr: "" },
  { name: "Ludes",   min: 11,    max: 60,    cheap: true,  expensive: false, cheapStr: "Rival drug dealers raided a pharmacy and are selling cheap ludes!" },
  { name: "MDA",     min: 1500,  max: 4400,  cheap: false, expensive: false, cheapStr: "" },
  { name: "Opium",   min: 540,   max: 1250,  cheap: false, expensive: true,  cheapStr: "" },
  { name: "PCP",     min: 1000,  max: 2500,  cheap: false, expensive: false, cheapStr: "" },
  { name: "Peyote",  min: 220,   max: 700,   cheap: false, expensive: false, cheapStr: "" },
  { name: "Shrooms", min: 630,   max: 1300,  cheap: false, expensive: false, cheapStr: "" },
  { name: "Speed",   min: 90,    max: 250,   cheap: false, expensive: true,  cheapStr: "" },
  { name: "Weed",    min: 315,   max: 890,   cheap: true,  expensive: false, cheapStr: "Columbian freighter dusted the Coast Guard! Weed prices have bottomed out!" }
]
var HASHISH = 2
var WEED = 11

var EXPENSIVE_STR1 = "Cops made a big %s bust! Prices are outrageous!"
var EXPENSIVE_STR2 = "Addicts are buying %s at ridiculous prices!"

var GUNS = [
  { name: "Baretta",                price: 3000, space: 4, damage: 5 },
  { name: ".38 Special",            price: 3500, space: 4, damage: 9 },
  { name: "Ruger",                  price: 2900, space: 4, damage: 4 },
  { name: "Saturday Night Special", price: 3100, space: 4, damage: 7 }
]

var COPS = [
  { name: "Officer Hardass", deputy: "deputy", deputies: "deputies", armor: 4,  deputyArmor: 3, attackPenalty: 30, defendPenalty: 30, minDeputies: 2, maxDeputies: 8,  gunIndex: 0, copGun: 1, deputyGun: 1 },
  { name: "Officer Bob",     deputy: "deputy", deputies: "deputies", armor: 15, deputyArmor: 4, attackPenalty: 30, defendPenalty: 20, minDeputies: 4, maxDeputies: 10, gunIndex: 0, copGun: 2, deputyGun: 1 },
  { name: "Agent Smith",     deputy: "cop",    deputies: "cops",     armor: 50, deputyArmor: 6, attackPenalty: 20, defendPenalty: 20, minDeputies: 6, maxDeputies: 18, gunIndex: 1, copGun: 3, deputyGun: 2 }
]

var STOPPED_TO = ["have a beer", "smoke a joint", "smoke a cigar", "smoke a Djarum", "smoke a cigarette"]

var PLAYING = [
  "`Are you Experienced` by Jimi Hendrix",
  "`Cheeba Cheeba` by Tone Loc",
  "`Comin` in to Los Angeles` by Arlo Guthrie",
  "`Commercial` by Spanky and Our Gang",
  "`Late in the Evening` by Paul Simon",
  "`Light Up` by Styx",
  "`Mexico` by Jefferson Airplane",
  "`One toke over the line` by Brewer & Shipley",
  "`The Smokeout` by Shel Silverstein",
  "`White Rabbit` by Jefferson Airplane",
  "`Itchycoo Park` by Small Faces",
  "`White Punks on Dope` by the Tubes",
  "`Legend of a Mind` by the Moody Blues",
  "`Eight Miles High` by the Byrds",
  "`Acapulco Gold` by Riders of the Purple Sage",
  "`Kicks` by Paul Revere & the Raiders",
  "the Nixon tapes",
  "`Legalize It` by Mojo Nixon & Skid Roper"
]

var SUBWAY_SAYINGS = [
  "Wouldn't it be funny if everyone suddenly quacked at once?",
  "The Pope was once Jewish, you know",
  "I'll bet you have some really interesting dreams",
  "So I think I'm going to Amsterdam this year",
  "Son, you need a yellow haircut",
  "I think it's wonderful what they're doing with incense these days",
  "I wasn't always a woman, you know",
  "Does your mother know you're a dope dealer?",
  "Are you high on something?",
  "Oh, you must be from California",
  "I used to be a hippie, myself",
  "There's nothing like having lots of money",
  "You look like an aardvark!",
  "I don't believe in Ronald Reagan",
  "Courage!  Bush is a noodle!",
  "Haven't I seen you on TV?",
  "I think hemorrhoid commercials are really neat!",
  "We're winning the war for drugs!",
  "A day without dope is like night",
  "We only use 20% of our brains, so why not burn out the other 80%",
  "I'm soliciting contributions for Zombies for Christ",
  "I'd like to sell you an edible poodle",
  "Winners don't do drugs... unless they do",
  "Kill a cop for Christ!",
  "I am the walrus!",
  "Jesus loves you more than you will know",
  "I feel an unaccountable urge to dye my hair blue",
  "Wasn't Jane Fonda wonderful in Barbarella",
  "Just say No... well, maybe... ok, what the hell!",
  "Would you like a jelly baby?",
  "Drugs can be your friend!"
]

var INTRO = [
  "Based on John E. Dell's old Drug Wars game, dopewars is a simulation of an imaginary drug market. dopewars is an All-American game which features buying, selling, and trying to get past the cops!",
  "The first thing you need to do is pay off your debt to the Loan Shark. After that, your goal is to make as much money as possible (and stay alive)!",
  "You have one month of game time to make your fortune."
]

// The server's event state machine (EventCode in dopewars.h).
var E = {
  NONE: 0, SUBWAY: 1, OFFOBJECT: 2, WEED: 3, SAYING: 4, LOANSHARK: 5, BANK: 6,
  GUNSHOP: 7, ROUGHPUB: 8, HIREBITCH: 9, ARRIVE: 10, MAX: 11,
  FINISH: 100, OUTOFSYNC: 120, FIGHT: 121, FIGHTASK: 122, DOCTOR: 123, WAITDONE: 124
}

// --------------------------------------------------------------- random ------

// mulberry32: small, fast, good enough for a game, and seedable so a whole
// game can be replayed from its seed.
function nextRandom(s) {
  s.rng = (s.rng + 0x6D2B79F5) | 0
  var t = s.rng
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

// brandom(bot, top) from dopewars: an integer in [bot, top-1].
function brandom(s, bot, top) {
  if (top <= bot) return bot
  return Math.floor((top - bot) * nextRandom(s)) + bot
}

// -------------------------------------------------------------- helpers ------

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

function pad2(n) { return (n < 10 ? "0" : "") + n }

// Names.Date default is "%m-%d-%Y".
function formatDate(date) {
  return pad2(date.m) + "-" + pad2(date.d) + "-" + date.y
}

function daysInMonth(m, y) {
  if (m === 2) return (y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0)) ? 29 : 28
  return [4, 6, 9, 11].indexOf(m) >= 0 ? 30 : 31
}

function addDay(date) {
  date.d += 1
  if (date.d > daysInMonth(date.m, date.y)) {
    date.d = 1
    date.m += 1
    if (date.m > 12) { date.m = 1; date.y += 1 }
  }
}

function totalGuns(guns) {
  var n = 0
  for (var i = 0; i < guns.length; i++) n += guns[i]
  return n
}

function sprintf(fmt) {
  var args = Array.prototype.slice.call(arguments, 1)
  var k = 0
  return fmt.replace(/%s/g, function() { return String(args[k++]) })
}

function initialCaps(text) {
  return text.length ? text.charAt(0).toUpperCase() + text.slice(1) : text
}

function log(s, text, kind) {
  s.log.push({ text: text, kind: kind || "info", turn: s.turn })
  if (s.log.length > LOG_LIMIT) s.log.splice(0, s.log.length - LOG_LIMIT)
  s.lastMessage = text
}

function ask(s, text, code) {
  s.prompt = { kind: "question", text: text, code: code }
}

function money(s) { return s.cash + s.bank - s.debt }

// ------------------------------------------------------------ new game ------

function newGame(name, seed) {
  var s = {
    version: 1,
    name: (String(name || "").trim() || "Dude").slice(0, MAX_NAME),
    rng: (seed === undefined || seed === null) ? (Date.now() & 0x7fffffff) : (seed | 0),
    seed: 0,
    turn: 1,
    date: { d: 1, m: 12, y: 1984 },
    cash: START_CASH,
    debt: START_DEBT,
    bank: 0,
    health: 100,
    coatSize: 100,       // free space, not capacity
    isAt: 0,
    guns: [],
    gunPrices: [],
    drugs: [],
    bitches: 8,
    bitchPrice: 0,
    eventNum: E.NONE,
    resyncNum: E.NONE,
    docPrice: 0,
    copIndex: 0,
    fight: null,
    prompt: null,
    log: [],
    lastMessage: "",
    finished: false,
    finishMessage: "",
    dead: false,
    score: 0,
    scored: false,
    scoreRank: -1
  }
  s.seed = s.rng
  for (var g = 0; g < GUNS.length; g++) { s.guns.push(0); s.gunPrices.push(0) }
  for (var d = 0; d < DRUGS.length; d++) s.drugs.push({ carried: 0, price: 0, totalValue: 0 })
  // C_NAME handler: the game opens with E_ARRIVE for the Bronx.
  log(s, "Hey dude, welcome to New York. You owe " + NAMES.loanShark + " " + formatPrice(s.debt) + ". You have one month of game time to make your fortune.", "turn")
  s.eventNum = E.ARRIVE
  sendEvent(s)
  return s
}

// ------------------------------------------------------------- prices -------

function clearPrices(s) {
  s.bitchPrice = 0
  for (var i = 0; i < s.gunPrices.length; i++) s.gunPrices[i] = 0
}

// GenerateDrugsHere + SendDrugsHere(DisplayBusts = true).
function generateDrugsHere(s) {
  var deal = []
  var i
  for (i = 0; i < DRUGS.length; i++) { s.drugs[i].price = 0; deal.push(0) }
  var numEvents = 0
  if (brandom(s, 0, 100) < 70) numEvents = 1
  if (brandom(s, 0, 100) < 40 && numEvents === 1) numEvents = 2
  if (brandom(s, 0, 100) < 5 && numEvents === 2) numEvents = 3
  var numDrugs = 0
  var guard = 0
  while (numEvents > 0 && guard++ < 1000) {
    i = brandom(s, 0, DRUGS.length)
    if (deal[i] !== 0) continue
    if (DRUGS[i].expensive && (!DRUGS[i].cheap || brandom(s, 0, 100) < 50)) {
      deal[i] = 2
      s.drugs[i].price = brandom(s, DRUGS[i].min, DRUGS[i].max) * EXPENSIVE_MULTIPLY
      numDrugs++; numEvents--
    } else if (DRUGS[i].cheap) {
      deal[i] = 1
      s.drugs[i].price = Math.floor(brandom(s, DRUGS[i].min, DRUGS[i].max) / CHEAP_DIVIDE)
      numDrugs++; numEvents--
    }
  }
  var loc = LOCATIONS[s.isAt]
  var numRandom = brandom(s, loc.minDrug, loc.maxDrug)
  if (numRandom > DRUGS.length) numRandom = DRUGS.length
  numDrugs = numRandom - numDrugs
  guard = 0
  while (numDrugs > 0 && guard++ < 10000) {
    i = brandom(s, 0, DRUGS.length)
    if (s.drugs[i].price === 0) {
      s.drugs[i].price = brandom(s, DRUGS[i].min, DRUGS[i].max)
      numDrugs--
    }
  }
  var lines = []
  for (i = 0; i < DRUGS.length; i++) {
    if (deal[i] === 1) lines.push(DRUGS[i].cheapStr)
    else if (deal[i] === 2) lines.push(sprintf(brandom(s, 0, 100) < 50 ? EXPENSIVE_STR1 : EXPENSIVE_STR2, DRUGS[i].name))
  }
  if (lines.length) log(s, lines.join("\n"), "prices")
}

// ------------------------------------------------------- event machine ------

function sendEvent(s) {
  if (s.eventNum === E.MAX) s.eventNum = E.NONE
  if (s.eventNum === E.NONE || s.eventNum >= E.OUTOFSYNC) return s
  var cash = money(s)
  clearPrices(s)
  while (s.eventNum < E.MAX) {
    switch (s.eventNum) {
    case E.SUBWAY:
      log(s, "S U B W A Y  →  " + LOCATIONS[s.isAt].name, "turn")
      break
    case E.OFFOBJECT:
      var range = cash > 3000000 ? 130 : (cash > 1000000 ? 115 : 100)
      if (brandom(s, 0, range) > 75) {
        if (sendCopOffer(s)) return s
      }
      break
    case E.WEED:
      break
    case E.SAYING:
      if (brandom(s, 0, 100) < 15) {
        if (brandom(s, 0, 100) < 50) {
          var saying = SUBWAY_SAYINGS[brandom(s, 0, SUBWAY_SAYINGS.length)]
          var unsure = brandom(s, 0, 100) < 30 ? "\n    (at least, you -think- that's what she said)" : ""
          log(s, "The lady next to you on the subway said,\n \"" + saying + "\"" + unsure, "event")
        } else {
          log(s, "You hear someone playing " + PLAYING[brandom(s, 0, PLAYING.length)], "event")
        }
      }
      break
    case E.LOANSHARK:
      if (s.isAt + 1 === LOAN_SHARK_LOC && s.debt > 0) {
        ask(s, "Would you like to visit " + NAMES.loanShark + "?", "loan")
        return s
      }
      break
    case E.BANK:
      if (s.isAt + 1 === BANK_LOC) {
        ask(s, "Would you like to visit " + NAMES.bank + "?", "bank")
        return s
      }
      break
    case E.GUNSHOP:
      if (s.isAt + 1 === GUN_SHOP_LOC) {
        ask(s, "Would you like to visit " + NAMES.gunShop + "?", "gunshop")
        return s
      }
      break
    case E.ROUGHPUB:
      if (s.isAt + 1 === ROUGH_PUB_LOC) {
        ask(s, "Would you like to visit " + NAMES.pub + "?", "pub")
        return s
      }
      break
    case E.HIREBITCH:
      if (s.isAt + 1 === ROUGH_PUB_LOC) {
        s.bitchPrice = brandom(s, BITCH_MIN_PRICE, BITCH_MAX_PRICE)
        ask(s, "Would you like to hire a " + NAMES.bitch + " for " + formatPrice(s.bitchPrice) + "?", "hirebitch")
        return s
      }
      break
    case E.ARRIVE:
      generateDrugsHere(s)
      break
    }
    s.eventNum++
  }
  if (s.eventNum >= E.MAX) s.eventNum = E.NONE
  return s
}

// SendCopOffer(To, NOFORCE): returns true when a question or fight is pending.
function sendCopOffer(s) {
  var i = brandom(s, 0, 80 + LOCATIONS[s.isAt].police)
  if (i < 33) return offerObject(s)
  if (i < 50) return randomOffer(s)
  copsAttackPlayer(s)
  return true
}

function offerObject(s) {
  if (brandom(s, 0, 100) < 50) {
    s.bitchPrice = Math.floor(brandom(s, BITCH_MIN_PRICE, BITCH_MAX_PRICE) / 10)
    ask(s, "Hey dude! I'll help carry your " + NAMES.drugs + " for a mere " + formatPrice(s.bitchPrice) + ". Yes or no?", "offer")
    return true
  }
  if (totalGuns(s.guns) < s.bitches + 2) {
    var obj = brandom(s, 0, GUNS.length)
    s.gunPrices[obj] = Math.floor(GUNS[obj].price / 10)
    if (GUNS[obj].space > s.coatSize) return false
    ask(s, "Would you like to buy a " + GUNS[obj].name + " for " + formatPrice(s.gunPrices[obj]) + "?", "offer")
    return true
  }
  return false
}

// IsCarryingRandom: up to five tries to find a drug carried in quantity.
function isCarryingRandom(s, amount) {
  for (var tries = 0; tries < 5; tries++) {
    var ind = brandom(s, 0, DRUGS.length)
    if (s.drugs[ind].carried >= amount) return ind
  }
  return -1
}

function removeDrugs(s, ind, amount) {
  var d = s.drugs[ind]
  if (d.carried > 0) d.totalValue = Math.floor(d.totalValue * (d.carried - amount) / d.carried)
  d.carried -= amount
  s.coatSize += amount
  if (d.carried <= 0) { d.carried = 0; d.totalValue = 0 }
}

function randomOffer(s) {
  var r = brandom(s, 0, 100)
  var amount, ind
  if (r < 10) {
    log(s, "You were mugged in the subway!", "danger")
    s.cash = Math.floor(s.cash * brandom(s, 80, 95) / 100)
  } else if (r < 30) {
    amount = brandom(s, 3, 7)
    ind = isCarryingRandom(s, amount)
    if (ind === -1 && amount > s.coatSize) return false
    if (ind === -1) {
      ind = brandom(s, 0, DRUGS.length)
      log(s, "You meet a friend! He gives you " + amount + " " + DRUGS[ind].name + ".", "event")
      s.drugs[ind].carried += amount
      s.coatSize -= amount
    } else {
      log(s, "You meet a friend! You give him " + amount + " " + DRUGS[ind].name + ".", "event")
      removeDrugs(s, ind, amount)
    }
  } else if (r < 50) {
    amount = brandom(s, 3, 7)
    ind = isCarryingRandom(s, amount)
    if (ind !== -1) {
      log(s, "Police dogs chase you for " + brandom(s, 3, 7) + " blocks! You dropped some " + NAMES.drugs + "! That's a drag, man!", "danger")
      removeDrugs(s, ind, amount)
    } else {
      ind = brandom(s, 0, DRUGS.length)
      amount = brandom(s, 3, 7)
      if (amount > s.coatSize) return false
      log(s, "You find " + amount + " " + DRUGS[ind].name + " on a dead dude in the subway!", "event")
      s.drugs[ind].carried += amount
      s.coatSize -= amount
    }
  } else if (r < 60 && s.drugs[WEED].carried + s.drugs[HASHISH].carried > 0) {
    ind = s.drugs[WEED].carried > s.drugs[HASHISH].carried ? WEED : HASHISH
    amount = brandom(s, 2, 6)
    if (amount > s.drugs[ind].carried) amount = s.drugs[ind].carried
    log(s, "Your mama made brownies with some of your " + DRUGS[ind].name + "! They were great!", "event")
    removeDrugs(s, ind, amount)
  } else if (r < 65) {
    s.eventNum = E.WEED
    ask(s, "There is some weed that smells like paraquat here!\nIt looks good! Will you smoke it?", "weed")
    return true
  } else {
    log(s, "You stopped to " + STOPPED_TO[brandom(s, 0, STOPPED_TO.length)] + ".", "event")
    amount = brandom(s, 1, 10)
    if (s.cash >= amount) s.cash -= amount
  }
  return false
}

// -------------------------------------------------------------- answers -----

// HandleAnswer for every yes/no question the game asks.
function answer(s, yes) {
  if (s.eventNum === E.NONE || !s.prompt || s.prompt.kind !== "question") return s
  yes = yes === true
  s.prompt = null
  if (yes && s.eventNum === E.OFFOBJECT && s.bitchPrice !== 0 && s.bitchPrice > s.cash) yes = false
  if (yes) {
    switch (s.eventNum) {
    case E.OFFOBJECT:
      if (s.bitchPrice !== 0) {
        buyBitch(s)
      } else {
        for (var i = 0; i < GUNS.length; i++) {
          if (s.gunPrices[i] !== 0) { tradeGun(s, i, 1); break }
        }
      }
      s.eventNum++
      return sendEvent(s)
    case E.LOANSHARK:
      s.prompt = { kind: "shop", shop: "loan" }
      return s
    case E.BANK:
      s.prompt = { kind: "shop", shop: "bank" }
      return s
    case E.GUNSHOP:
      for (var g = 0; g < GUNS.length; g++) s.gunPrices[g] = GUNS[g].price
      s.prompt = { kind: "shop", shop: "gunshop" }
      return s
    case E.HIREBITCH:
      buyBitch(s)
      s.eventNum++
      return sendEvent(s)
    case E.ROUGHPUB:
      s.eventNum++
      return sendEvent(s)
    case E.WEED:
      return finishGame(s, "You hallucinated for three days on the wildest trip you ever imagined!\nThen you died because your brain disintegrated!")
    case E.DOCTOR:
      if (s.cash >= s.docPrice) {
        s.cash -= s.docPrice
        s.health = 100
        log(s, "The doctor sews you up. You feel much better.", "info")
      } else {
        log(s, "You can't afford the doctor.", "info")
      }
      return waitForFightDone(s)
    }
    s.eventNum++
    return sendEvent(s)
  }
  switch (s.eventNum) {
  case E.ROUGHPUB:
    s.eventNum += 2
    return sendEvent(s)
  case E.DOCTOR:
    return waitForFightDone(s)
  default:
    s.eventNum++
    return sendEvent(s)
  }
}

// C_DONE from a shop: the client sends it when the player leaves.
function leaveShop(s) {
  if (!s.prompt || s.prompt.kind !== "shop") return s
  if (s.eventNum === E.LOANSHARK || s.eventNum === E.BANK || s.eventNum === E.GUNSHOP) {
    s.prompt = null
    s.eventNum++
    return sendEvent(s)
  }
  return s
}

// ---------------------------------------------------------------- shops -----

// C_PAYLOAN
function payLoan(s, amount) {
  amount = Math.trunc(Number(amount) || 0)
  if (s.eventNum !== E.LOANSHARK) return { ok: false, error: "" }
  if (amount <= 0) return { ok: false, error: "" }
  if (amount > s.debt) amount = s.debt
  if (amount > s.cash) return { ok: false, error: "You don't have that much money!" }
  s.debt -= amount
  s.cash -= amount
  log(s, "You pay " + NAMES.loanShark + " " + formatPrice(amount) + ".", "info")
  return { ok: true, error: "" }
}

// C_DEPOSIT with a signed amount: positive deposits, negative withdraws.
function bankMove(s, amount) {
  amount = Math.trunc(Number(amount) || 0)
  if (s.eventNum !== E.BANK || amount === 0) return { ok: false, error: "" }
  if (amount > 0 && amount > s.cash) return { ok: false, error: "You don't have that much money!" }
  if (amount < 0 && -amount > s.bank) return { ok: false, error: "There isn't that much money in the bank..." }
  s.bank += amount
  s.cash -= amount
  log(s, amount > 0 ? "You deposit " + formatPrice(amount) + "." : "You withdraw " + formatPrice(-amount) + ".", "info")
  return { ok: true, error: "" }
}

// BuyObject "gun^index^amount". Used by the gun shop, random gun offers and
// loot. Returns false when the server would reject it.
function tradeGun(s, index, amount) {
  if (index < 0 || index >= GUNS.length) return false
  var total = totalGuns(s.guns)
  if (total + amount < 0) return false
  if (total + amount > s.bitches + 2) return false
  if (s.gunPrices[index] === 0) return false
  if (s.coatSize - amount * GUNS[index].space < 0) return false
  if (s.cash < amount * s.gunPrices[index]) return false
  s.guns[index] += amount
  s.coatSize -= amount * GUNS[index].space
  s.cash -= amount * s.gunPrices[index]
  return true
}

// The gun shop's own checks, with the curses client's error strings.
function buyGun(s, index) {
  if (s.eventNum !== E.GUNSHOP) return { ok: false, error: "" }
  if (totalGuns(s.guns) >= s.bitches + 2) return { ok: false, error: "You'll need more " + NAMES.bitches + " to carry any more " + NAMES.guns + "!" }
  if (GUNS[index].space > s.coatSize) return { ok: false, error: "You don't have enough space to carry that " + NAMES.gun + "!" }
  if (s.gunPrices[index] > s.cash) return { ok: false, error: "You don't have enough cash to buy that " + NAMES.gun + "!" }
  var ok = tradeGun(s, index, 1)
  if (ok) log(s, "You buy a " + GUNS[index].name + " for " + formatPrice(s.gunPrices[index]) + ".", "info")
  return { ok: ok, error: "" }
}

function sellGun(s, index) {
  if (s.eventNum !== E.GUNSHOP) return { ok: false, error: "" }
  if (totalGuns(s.guns) === 0) return { ok: false, error: "You don't have any " + NAMES.guns + " to sell!" }
  if (s.guns[index] === 0) return { ok: false, error: "You don't have any to sell!" }
  var ok = tradeGun(s, index, -1)
  if (ok) log(s, "You sell a " + GUNS[index].name + " for " + formatPrice(s.gunPrices[index]) + ".", "info")
  return { ok: ok, error: "" }
}

// BuyObject "bitch^0^1"
function buyBitch(s) {
  if (s.bitchPrice === 0 || s.bitchPrice > s.cash) return false
  gainBitch(s)
  s.cash -= s.bitchPrice
  log(s, "A new " + NAMES.bitch + " joins you for " + formatPrice(s.bitchPrice) + ".", "info")
  return true
}

function gainBitch(s) {
  s.coatSize += 10
  s.bitches += 1
}

// LoseBitch(Play, NULL, NULL): the coat shrinks, maybe a gun goes, and every
// drug loses its share.
function loseBitch(s) {
  s.coatSize -= 10
  var tg = totalGuns(s.guns)
  if (tg > 0 && brandom(s, 0, 100) < Math.floor(tg * 100 / (s.bitches + 2))) {
    var order = []
    for (var g = 0; g < GUNS.length; g++) order.push(g)
    for (var k = order.length - 1; k > 0; k--) {
      var j = brandom(s, 0, k + 1)
      var tmp = order[k]; order[k] = order[j]; order[j] = tmp
    }
    for (var o = 0; o < order.length; o++) {
      if (s.guns[order[o]] > 0) {
        s.guns[order[o]]--
        s.coatSize += GUNS[order[o]].space
        break
      }
    }
  }
  for (var i = 0; i < DRUGS.length; i++) {
    var d = s.drugs[i]
    if (d.carried > 0) {
      var num = Math.floor(d.carried / (s.bitches + 2.0) + 0.5)
      if (num > 0) removeDrugs(s, i, num)
    }
  }
  var guard = 0
  while (s.coatSize < 0 && guard++ < 10000) {
    var dropped = false
    for (var di = 0; di < DRUGS.length && s.coatSize < 0; di++) {
      if (s.drugs[di].carried > 0) { removeDrugs(s, di, 1); dropped = true }
    }
    if (!dropped) {
      for (var gi = 0; gi < GUNS.length && s.coatSize < 0; gi++) {
        if (s.guns[gi] > 0) { s.guns[gi]--; s.coatSize += GUNS[gi].space; dropped = true }
      }
    }
    if (!dropped) break
  }
  s.bitches -= 1
}

// ---------------------------------------------------------------- drugs -----

// BuyObject "drug^index^amount": amount > 0 buys, < 0 sells (or drops when
// the drug is not on sale here).
function tradeDrug(s, index, amount) {
  amount = Math.trunc(Number(amount) || 0)
  if (s.eventNum !== E.NONE || s.finished || s.prompt) return false
  if (index < 0 || index >= DRUGS.length || amount === 0) return false
  var d = s.drugs[index]
  if (d.carried + amount < 0) return false
  if (s.coatSize - amount < 0) return false
  if (d.price === 0 && amount > 0) return false
  if (s.cash < amount * d.price) return false
  if (amount > 0) d.totalValue += amount * d.price
  else if (d.carried !== 0) d.totalValue = Math.floor(d.totalValue * (d.carried + amount) / d.carried)
  d.carried += amount
  s.coatSize -= amount
  s.cash -= amount * d.price
  if (d.carried === 0) d.totalValue = 0
  if (amount > 0) log(s, "You buy " + amount + " " + DRUGS[index].name + " for " + formatPrice(amount * d.price) + ".", "info")
  else if (d.price > 0) log(s, "You sell " + (-amount) + " " + DRUGS[index].name + " for " + formatPrice(-amount * d.price) + ".", "info")
  else log(s, "You drop " + (-amount) + " " + DRUGS[index].name + ".", "info")
  if (d.price === 0 && brandom(s, 0, 100) < LOCATIONS[s.isAt].police) {
    log(s, "The cops spot you dropping " + NAMES.drugs + "!", "danger")
    copsAttackPlayer(s)
  }
  return true
}

function buyDrug(s, index, amount) { return tradeDrug(s, index, Math.abs(amount)) }
function sellDrug(s, index, amount) { return tradeDrug(s, index, -Math.abs(amount)) }

function canAfford(s, index) {
  var price = s.drugs[index].price
  return price > 0 ? Math.floor(s.cash / price) : 0
}

// Drugs on sale here, sorted A to Z (DrugSortMethod default DS_ATOZ).
function drugsHere(s) {
  var out = []
  for (var i = 0; i < DRUGS.length; i++) {
    if (s.drugs[i].price > 0) out.push({ index: i, name: DRUGS[i].name, price: s.drugs[i].price, carried: s.drugs[i].carried })
  }
  out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0) })
  return out
}

// What is in the trenchcoat, with the average price paid.
function carriedDrugs(s) {
  var out = []
  for (var i = 0; i < DRUGS.length; i++) {
    var d = s.drugs[i]
    if (d.carried > 0) out.push({ index: i, name: DRUGS[i].name, carried: d.carried, avg: Math.floor(d.totalValue / d.carried), price: d.price })
  }
  return out
}

function carriedGuns(s) {
  var out = []
  for (var i = 0; i < GUNS.length; i++) if (s.guns[i] > 0) out.push({ index: i, name: GUNS[i].name, carried: s.guns[i] })
  return out
}

function hasWorthless(s) {
  for (var i = 0; i < DRUGS.length; i++) if (s.drugs[i].carried > 0 && s.drugs[i].price === 0) return true
  return false
}

// -------------------------------------------------------------- jetting -----

function jet(s, to) {
  to = Number(to)
  if (s.finished || to < 0 || to >= LOCATIONS.length) return s
  if (s.eventNum === E.FIGHT || s.eventNum === E.FIGHTASK) return s
  if (s.turn >= NUM_TURNS && s.eventNum !== E.FINISH) {
    return finishGame(s, "Your dealing time is up...")
  }
  if (to !== s.isAt && s.turn < NUM_TURNS && s.eventNum === E.NONE && s.health > 0) {
    s.isAt = to
    s.turn += 1
    addDay(s.date)
    s.debt = Math.max(0, Math.floor(s.debt * (DEBT_INTEREST + 100) / 100))
    s.bank = Math.max(0, Math.floor(s.bank * (BANK_INTEREST + 100) / 100))
    s.eventNum = E.SUBWAY
    sendEvent(s)
  }
  return s
}

// --------------------------------------------------------------- fights -----

function armament(guns, bitches) {
  var damage = 0, maxDamage = 0
  for (var i = 0; i < GUNS.length; i++) {
    damage += GUNS[i].damage * guns[i]
    if (GUNS[i].damage > maxDamage) maxDamage = GUNS[i].damage
  }
  maxDamage *= bitches + 2
  var pct = maxDamage > 0 ? Math.floor(damage * 100 / maxDamage) : 0
  if (pct < 10) return "pitifully armed"
  if (pct < 25) return "lightly armed"
  if (pct < 60) return "moderately well armed"
  if (pct < 80) return "heavily armed"
  return "armed to the teeth"
}

function fightLog(s, text) {
  s.fight.messages.push(text)
  if (s.fight.messages.length > 12) s.fight.messages.splice(0, s.fight.messages.length - 12)
  log(s, text, "fight")
}

// CopsAttackPlayer + AttackPlayer: pick the cop, roll deputies and guns,
// announce, and let the cops shoot first.
function copsAttackPlayer(s) {
  var copIndex = 1 - s.copIndex
  if (copIndex > COPS.length) copIndex = COPS.length
  var cop = COPS[copIndex - 1]
  var deputies = brandom(s, cop.minDeputies, cop.maxDeputies)
  var gunIndex = Math.min(cop.gunIndex, GUNS.length - 1)
  var guns = []
  for (var g = 0; g < GUNS.length; g++) guns.push(0)
  guns[gunIndex] = deputies * cop.deputyGun + cop.copGun
  s.fight = {
    copIndex: copIndex,
    name: cop.name,
    cash: brandom(s, 100, 2000),
    deputies: deputies,
    guns: guns,
    health: 100,
    coatSize: 100,
    over: false,
    escaped: false,
    killed: false,
    messages: []
  }
  s.eventNum += 1
  s.resyncNum = s.eventNum
  s.eventNum = E.FIGHT
  s.prompt = { kind: "fight" }
  var arm = armament(s.guns, s.bitches)
  if (deputies > 0) fightLog(s, cop.name + " and " + deputies + " " + cop.deputies + " - " + arm + " - are chasing you, man!")
  else fightLog(s, cop.name + " - " + arm + " - is chasing you, man!")
  copFire(s)
}

function copLoseDeputy(s) {
  var f = s.fight
  f.coatSize -= 10
  var tg = totalGuns(f.guns)
  if (tg > 0 && brandom(s, 0, 100) < Math.floor(tg * 100 / (f.deputies + 2))) {
    for (var g = 0; g < GUNS.length; g++) {
      if (f.guns[g] > 0) { f.guns[g]--; f.coatSize += GUNS[g].space; break }
    }
  }
  f.deputies -= 1
}

// The cop's turn. Returns true if the player is still alive.
function copFire(s) {
  var f = s.fight
  if (!f || f.over) return true
  var cop = COPS[f.copIndex - 1]
  if (totalGuns(f.guns) > 0) {
    var attack = 80
    for (var i = 0; i < GUNS.length; i++) attack += GUNS[i].damage * f.guns[i]
    attack -= cop.attackPenalty
    var defend = 100 - 5 * s.bitches
    attack = Math.max(attack, 10)
    defend = Math.max(defend, 10)
    if (brandom(s, 0, attack) > brandom(s, 0, defend)) {
      var damage = 0
      for (var gi = 0; gi < GUNS.length; gi++) {
        for (var n = 0; n < f.guns[gi]; n++) damage += brandom(s, 0, GUNS[gi].damage)
      }
      damage = Math.floor(damage * 100 / (s.bitches === 0 ? PLAYER_ARMOR : BITCH_ARMOR))
      if (damage === 0) damage = 1
      if (s.health <= damage && s.bitches === 0) {
        s.health = 0
        fightLog(s, f.name + " wasted you, man! What a drag!")
        f.over = true
        finishGame(s, "You're dead! Game over.")
        return false
      } else if (s.bitches > 0 && s.health <= damage) {
        loseBitch(s)
        s.health = 100
        fightLog(s, f.name + " shoots at you... and kills a " + NAMES.bitch + "!")
      } else {
        s.health -= damage
        fightLog(s, f.name + " hits you, man!")
      }
    } else {
      fightLog(s, f.name + " shoots at you... and misses!")
    }
  } else {
    fightLog(s, f.name + " stands and takes it")
  }
  return true
}

// TruncateInventoryFor + the loot hand-over: take what the cop had, within
// the gun limit and the coat.
function lootGuns(s, guns) {
  var order = []
  for (var i = 0; i < GUNS.length; i++) order.push(i)
  order.sort(function(a, b) { return GUNS[b].price - GUNS[a].price })
  var taken = 0
  for (var o = 0; o < order.length; o++) {
    var g = order[o]
    while (guns[g] > 0 && totalGuns(s.guns) < s.bitches + 2 && s.coatSize >= GUNS[g].space) {
      guns[g]--
      s.guns[g]++
      s.coatSize -= GUNS[g].space
      taken++
    }
  }
  return taken
}

function playerFire(s) {
  var f = s.fight
  var cop = COPS[f.copIndex - 1]
  if (totalGuns(s.guns) > 0) {
    var attack = 80
    for (var i = 0; i < GUNS.length; i++) attack += GUNS[i].damage * s.guns[i]
    var defend = 100 - 5 * f.deputies - cop.defendPenalty
    attack = Math.max(attack, 10)
    defend = Math.max(defend, 10)
    if (brandom(s, 0, attack) > brandom(s, 0, defend)) {
      var damage = 0
      for (var gi = 0; gi < GUNS.length; gi++) {
        for (var n = 0; n < s.guns[gi]; n++) damage += brandom(s, 0, GUNS[gi].damage)
      }
      damage = Math.floor(damage * 100 / (f.deputies === 0 ? cop.armor : cop.deputyArmor))
      if (damage === 0) damage = 1
      if (f.health <= damage && f.deputies === 0) {
        f.health = 0
        var bounty = f.cash
        var taken = lootGuns(s, f.guns)
        s.cash += bounty
        var text = "You killed " + f.name + "!"
        if (bounty > 0) text += " You find " + formatPrice(bounty) + " on the body!"
        else if (taken > 0) text += " You loot the body!"
        fightLog(s, text)
        f.killed = true
        f.over = true
        s.copIndex = -f.copIndex
        return true
      } else if (f.deputies > 0 && f.health <= damage) {
        copLoseDeputy(s)
        f.health = 100
        fightLog(s, "You hit " + f.name + ", and killed a " + cop.deputy + "!")
      } else {
        f.health -= damage
        fightLog(s, "You hit " + f.name + "!")
      }
    } else {
      fightLog(s, "You missed " + f.name + "!")
    }
  } else {
    fightLog(s, "You stand there like a dummy.")
  }
  return false
}

function waitForFightDone(s) {
  s.eventNum = E.WAITDONE
  s.prompt = { kind: "fightdone" }
  return s
}

// The cop is dead and has left: maybe a doctor turns up.
function afterCopKilled(s) {
  if (brandom(s, 0, 100) > LOCATIONS[s.isAt].police) {
    s.eventNum = E.DOCTOR
    s.docPrice = Math.floor(brandom(s, BITCH_MIN_PRICE, BITCH_MAX_PRICE) * s.health / 500)
    ask(s, "Do you pay a doctor " + formatPrice(s.docPrice) + " to sew you up?", "doctor")
    return s
  }
  return waitForFightDone(s)
}

// C_FIGHTACT: "F" fight, "S" stand, "R" run.
function fightAction(s, action) {
  if (!s.fight || s.fight.over || s.eventNum !== E.FIGHT) return s
  action = String(action || "F").toUpperCase()
  if (action === "R") {
    if (brandom(s, 0, 100) < 60) {
      if (brandom(s, 0, 100) < 30) s.copIndex -= 1
      s.fight.over = true
      s.fight.escaped = true
      fightLog(s, "You got away!")
      return waitForFightDone(s)
    }
    fightLog(s, "Panic! You can't get away!")
    copFire(s)
    return s
  }
  if (playerFire(s)) return afterCopKilled(s)
  copFire(s)
  return s
}

// "D>eal drugs" after the fight: resume the event chain where it left off.
function fightDone(s) {
  if (s.eventNum !== E.WAITDONE) return s
  s.fight = null
  s.prompt = null
  s.eventNum = s.resyncNum
  return sendEvent(s)
}

// ------------------------------------------------------------ game over -----

function finishGame(s, message) {
  s.eventNum = E.FINISH
  s.finished = true
  s.finishMessage = message || ""
  s.dead = s.health === 0
  s.score = money(s)
  s.prompt = { kind: "gameover" }
  if (message) log(s, message, "turn")
  return s
}

function quitGame(s) {
  if (s.finished) return s
  return finishGame(s, "")
}

// SendHighScores: insert into the table, newest wins ties by rank. Returns
// the rank (0-based) or -1. Mutates `scores`.
function recordScore(scores, s) {
  if (s.scored) return s.scoreRank
  s.scored = true
  var now = new Date()
  var entry = {
    money: s.score,
    name: s.name,
    date: pad2(now.getUTCDate()) + "-" + pad2(now.getUTCMonth() + 1) + "-" + now.getUTCFullYear(),
    dead: s.dead,
    turn: s.turn
  }
  var rank = -1
  for (var i = 0; i < NUM_HISCORE; i++) {
    if (i >= scores.length || entry.money > scores[i].money) { rank = i; break }
  }
  if (rank >= 0) {
    scores.splice(rank, 0, entry)
    if (scores.length > NUM_HISCORE) scores.length = NUM_HISCORE
    log(s, "Congratulations! You made the high scores!", "turn")
  } else {
    log(s, "You didn't even make the high score table...", "turn")
  }
  s.scoreRank = rank
  return rank
}

// ------------------------------------------------------------ view model ----

// Which screen the UI should show.
function mode(s) {
  if (!s) return "none"
  if (s.finished) return "gameover"
  if (!s.prompt) return "street"
  if (s.prompt.kind === "question") return "question"
  if (s.prompt.kind === "shop") return s.prompt.shop
  if (s.prompt.kind === "fight") return "fight"
  if (s.prompt.kind === "fightdone") return "fightdone"
  return "street"
}

function statusLine(s) {
  return "Day " + s.turn + " of " + NUM_TURNS + "  ·  " + formatDate(s.date)
}

// Sanity checks, used by the tests and by the loader to reject a corrupt save.
// The save file is the only untrusted input the game has (settings aside):
// every number must be a finite integer in range, every string a bounded
// string, every list the right shape, so a hand-edited or corrupt file can
// neither crash the shell nor smuggle anything into the UI.
var MAX_MONEY = 1e15
var MAX_TEXT = 400
var MAX_NAME = 40

function isInt(v, lo, hi) {
  return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= lo && v <= hi
}
function isText(v, max) { return typeof v === "string" && v.length <= max }

function validate(s) {
  if (!s || typeof s !== "object" || Array.isArray(s)) return "no state"
  if (!isText(s.name, MAX_NAME) || s.name === "") return "bad name"
  if (!isInt(s.rng, -2147483648, 2147483647)) return "bad rng"
  if (!isInt(s.turn, 1, NUM_TURNS)) return "bad turn"
  if (!s.date || !isInt(s.date.d, 1, 31) || !isInt(s.date.m, 1, 12) || !isInt(s.date.y, 1900, 9999)) return "bad date"
  if (!isInt(s.cash, 0, MAX_MONEY)) return "bad cash"
  if (!isInt(s.bank, 0, MAX_MONEY)) return "bad bank"
  if (!isInt(s.debt, 0, MAX_MONEY)) return "bad debt"
  if (!isInt(s.health, 0, 100)) return "bad health"
  if (!isInt(s.coatSize, 0, 100000)) return "bad coat"
  if (!isInt(s.bitches, 0, 10000)) return "bad bitches"
  if (!isInt(s.bitchPrice, 0, MAX_MONEY)) return "bad bitch price"
  if (!isInt(s.docPrice, 0, MAX_MONEY)) return "bad doctor price"
  if (!isInt(s.copIndex, -1000000, 0)) return "bad cop index"
  if (!isInt(s.isAt, 0, LOCATIONS.length - 1)) return "bad location"
  if (!isInt(s.eventNum, 0, 200) || !isInt(s.resyncNum, 0, 200)) return "bad event"
  if (!isInt(s.scoreRank, -1, NUM_HISCORE)) return "bad rank"
  if (typeof s.finished !== "boolean" || typeof s.dead !== "boolean" || typeof s.scored !== "boolean") return "bad flags"
  if (!isText(s.finishMessage, MAX_TEXT) || !isText(s.lastMessage, MAX_TEXT)) return "bad message"
  if (!Array.isArray(s.drugs) || s.drugs.length !== DRUGS.length) return "bad drugs"
  if (!Array.isArray(s.guns) || s.guns.length !== GUNS.length) return "bad guns"
  if (!Array.isArray(s.gunPrices) || s.gunPrices.length !== GUNS.length) return "bad gun prices"
  if (!Array.isArray(s.log) || s.log.length > LOG_LIMIT) return "bad log"
  for (var l = 0; l < s.log.length; l++) {
    if (!s.log[l] || !isText(s.log[l].text, MAX_TEXT) || !isText(s.log[l].kind, 16)) return "bad log entry"
  }
  if (s.prompt !== null) {
    if (!s.prompt || typeof s.prompt !== "object") return "bad prompt"
    if (!isText(s.prompt.kind, 16)) return "bad prompt kind"
    if (s.prompt.kind === "question" && (!isText(s.prompt.text, MAX_TEXT) || !isText(s.prompt.code, 16))) return "bad question"
    if (s.prompt.kind === "shop" && ["loan", "bank", "gunshop"].indexOf(s.prompt.shop) < 0) return "bad shop"
    if (["question", "shop", "fight", "fightdone", "gameover"].indexOf(s.prompt.kind) < 0) return "unknown prompt"
  }
  if (s.fight !== null) {
    var f = s.fight
    if (!f || typeof f !== "object") return "bad fight"
    if (!isInt(f.copIndex, 1, COPS.length) || !isText(f.name, MAX_NAME)) return "bad fight cop"
    if (!isInt(f.cash, 0, MAX_MONEY) || !isInt(f.deputies, 0, 10000) || !isInt(f.health, 0, 100) || !isInt(f.coatSize, -100000, 100000)) return "bad fight numbers"
    if (typeof f.over !== "boolean" || typeof f.escaped !== "boolean" || typeof f.killed !== "boolean") return "bad fight flags"
    if (!Array.isArray(f.guns) || f.guns.length !== GUNS.length) return "bad fight guns"
    for (var fg = 0; fg < f.guns.length; fg++) if (!isInt(f.guns[fg], 0, 100000)) return "bad fight gun"
    if (!Array.isArray(f.messages) || f.messages.length > 12) return "bad fight messages"
    for (var fm = 0; fm < f.messages.length; fm++) if (!isText(f.messages[fm], MAX_TEXT)) return "bad fight message"
  } else if (s.prompt && (s.prompt.kind === "fight" || s.prompt.kind === "fightdone")) {
    return "fight prompt without a fight"
  }
  var used = 0
  for (var i = 0; i < DRUGS.length; i++) {
    var d = s.drugs[i]
    if (!d || !isInt(d.carried, 0, 100000) || !isInt(d.price, 0, MAX_MONEY) || !isInt(d.totalValue, 0, MAX_MONEY)) return "bad drug"
    used += d.carried
  }
  for (var g = 0; g < GUNS.length; g++) {
    if (!isInt(s.guns[g], 0, 100000) || !isInt(s.gunPrices[g], 0, MAX_MONEY)) return "bad gun"
    used += s.guns[g] * GUNS[g].space
  }
  // A new player has 100 space and 8 bitches; each bitch gained or lost
  // since then moves the total by 10.
  if (used + s.coatSize !== 20 + 10 * s.bitches) return "coat mismatch: used " + used + " free " + s.coatSize + " bitches " + s.bitches
  if (totalGuns(s.guns) > s.bitches + 2) return "too many guns"
  return ""
}

// The high score table from the save file: drop anything that isn't a
// well-formed entry, keep at most NUM_HISCORE, keep them sorted.
function sanitizeScores(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < NUM_HISCORE; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    if (!isInt(e.money, -MAX_MONEY, MAX_MONEY) || !isText(e.name, MAX_NAME) || !isText(e.date, 16)) continue
    out.push({ money: e.money, name: e.name, date: e.date, dead: e.dead === true, turn: isInt(e.turn, 1, NUM_TURNS) ? e.turn : 0 })
  }
  out.sort(function(a, b) { return b.money - a.money })
  return out
}
