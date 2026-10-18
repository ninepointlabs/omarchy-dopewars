// Facts and text for the About page (AboutView.qml), kept out of QML so node
// can check them against the repo (see test/about.js).
//
// The version comes from manifest.json and the license text from LICENSE at
// run time, so neither is copied here and neither can drift from the file.

var NAME = "Dopewars"
var TAGLINE = "The classic dopewars (Drug Wars) trading game, single player, in a bar panel."
var ORGANIZATION = "Nine Point Labs"
var CREATED = "September 2026" // first commit: 2026-09-08
var LICENSE = "GNU General Public License v2 only (GPL-2.0-only)"
var SUPPORT_EMAIL = "help@ninepointlabs.com"
// As README.md and Game.js credit it.
var CREDITS = "Based on dopewars 1.6.2, Copyright (C) Ben Webb 1998–2022 (GPL-2.0), "
  + "itself based on John E. Dell's 1984 Drug Wars."

// Must stay true to the code: no network (test/about.js checks), one
// subprocess (mkdir -p for the state dir), one file written by the plugin.
var PRIVACY = "No network access, no accounts and no telemetry; the game makes no connections at all. "
  + "Your game and the high score table (with the player names in it) are saved to "
  + "~/.local/state/omarchy-dopewars/save.json after every move, with your default file "
  + "permissions (0644 under the usual umask); delete that folder to wipe them. The widget's settings (player name, show status) "
  + "stay in ~/.config/omarchy/shell.json. It writes nothing anywhere else."

// "0.1.0" from manifest.json's text, or "" when it can't be read.
function manifestVersion(text) {
  try {
    var v = JSON.parse(String(text || "")).version
    return typeof v === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(v) ? v : ""
  } catch (e) {
    return ""
  }
}

// LICENSE with one line per paragraph, so it wraps to the panel's width.
function licenseBody(text) {
  var paras = String(text || "").replace(/\r/g, "").split(/\n\s*\n/)
  var out = []
  for (var i = 0; i < paras.length; i++) {
    var p = paras[i].split(/\s+/).join(" ").trim()
    if (p !== "") out.push(p)
  }
  return out.join("\n\n")
}

// Highest minor version `has(major, minor)` accepts, as "major.minor"
// (Quickshell.hasVersion / hasQtVersion only answer yes or no), or "".
function probedVersion(has, major) {
  if (typeof has !== "function" || !has(major, 0)) return ""
  var minor = 0
  while (minor < 99 && has(major, minor + 1)) minor++
  return major + "." + minor
}

function builtWith(quickshell, qt) {
  var out = []
  if (quickshell) out.push("Quickshell " + quickshell)
  if (qt) out.push("Qt " + qt)
  return out.length ? out.join(", ") : "Quickshell and Qt"
}

// Version details to paste into a support email.
function details(version, quickshell, qt, desktop) {
  return NAME + " " + (version || "unknown version") + "\n"
    + builtWith(quickshell, qt) + "\n"
    + (desktop || "unknown desktop")
}

function mailto(version, detailText) {
  return "mailto:" + SUPPORT_EMAIL
    + "?subject=" + encodeURIComponent(NAME + " " + (version || ""))
    + "&body=" + encodeURIComponent("\n\n--\n" + detailText)
}

if (typeof module !== "undefined") {
  module.exports = {
    NAME: NAME, TAGLINE: TAGLINE, ORGANIZATION: ORGANIZATION, CREATED: CREATED, LICENSE: LICENSE,
    SUPPORT_EMAIL: SUPPORT_EMAIL, CREDITS: CREDITS, PRIVACY: PRIVACY,
    manifestVersion: manifestVersion, licenseBody: licenseBody, probedVersion: probedVersion,
    builtWith: builtWith, details: details, mailto: mailto
  }
}
