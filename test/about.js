#!/usr/bin/env node
// Checks the About page's facts against the repo's own files (manifest.json,
// LICENSE, git history) and that the privacy statement stays true: the
// plugin makes no network connections. Run: node test/about.js
"use strict"

const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { execFileSync } = require("child_process")
const About = require("../About.js")

const ROOT = path.join(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(ROOT, name), "utf8")
let failures = 0

function check(name, fn) {
  try { fn(); console.log("ok   " + name) } catch (e) { failures++; console.error("FAIL " + name + "\n     " + e.message) }
}

check("version comes from manifest.json", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.strictEqual(About.manifestVersion(read("manifest.json")), manifest.version)
  assert.match(About.manifestVersion(read("manifest.json")), /^\d+\.\d+\.\d+$/)
  assert.strictEqual(About.manifestVersion("not json"), "")
  assert.strictEqual(About.manifestVersion('{"version":"1.0 <b>"}'), "")
  assert.strictEqual(About.NAME, manifest.name)
})

check("Nine Point Labs, spelled that way everywhere", () => {
  assert.strictEqual(About.ORGANIZATION, "Nine Point Labs")
  assert.strictEqual(JSON.parse(read("manifest.json")).author, "Nine Point Labs")
  for (const f of ["manifest.json", "README.md", "About.js", "AboutView.qml", "Panel.qml", "BarWidget.qml", "Service.qml", "Game.js", "install.sh"])
    assert.ok(!/ninepoint labs/i.test(read(f)), f)
})

check("license is the GPL v2 in LICENSE, as manifest.json declares", () => {
  const text = read("LICENSE")
  assert.ok(/GNU GENERAL PUBLIC LICENSE\s+Version 2, June 1991/.test(text))
  assert.strictEqual(JSON.parse(read("manifest.json")).license, "GPL-2.0-only")
  assert.ok(About.LICENSE.includes("GPL-2.0-only"))
  const body = About.licenseBody(text)
  assert.ok(body.startsWith("GNU GENERAL PUBLIC LICENSE Version 2, June 1991\n\n"), body.substring(0, 60))
  assert.ok(body.includes("NO WARRANTY"))
  assert.ok(!/[^\n]\n[^\n]/.test(body), "one line per paragraph")
})

check("credits match how the repo credits dopewars", () => {
  assert.ok(read("README.md").includes("Copyright (C) Ben Webb 1998–2022"))
  assert.ok(About.CREDITS.includes("Copyright (C) Ben Webb 1998–2022"))
  assert.ok(About.CREDITS.includes("dopewars 1.6.2") && read("Game.js").includes("dopewars 1.6.2"))
  assert.ok(About.CREDITS.includes("John E. Dell's 1984 Drug Wars"))
})

check("created date is the first commit's month", () => {
  let first = ""
  try {
    first = execFileSync("git", ["log", "--reverse", "--format=%ad", "--date=format:%B %Y"], { cwd: ROOT, encoding: "utf8" }).split("\n")[0]
  } catch (e) { console.log("     (no git history; skipped)"); return }
  assert.strictEqual(About.CREATED, first)
})

check("support email and the prefilled mailto", () => {
  assert.strictEqual(About.SUPPORT_EMAIL, "help@ninepointlabs.com")
  const details = About.details("0.1.0", "0.3", "6.11", "Hyprland, wayland")
  assert.strictEqual(details, "Dopewars 0.1.0\nQuickshell 0.3, Qt 6.11\nHyprland, wayland")
  const url = About.mailto("0.1.0", details)
  assert.ok(url.startsWith("mailto:help@ninepointlabs.com?subject=Dopewars%200.1.0&body="), url)
  assert.strictEqual(decodeURIComponent(url.split("&body=")[1]), "\n\n--\n" + details)
  assert.strictEqual(About.builtWith("", ""), "Quickshell and Qt")
  assert.strictEqual(About.probedVersion((major, minor) => major === 6 && minor <= 11, 6), "6.11")
  assert.strictEqual(About.probedVersion(() => false, 0), "")
})

check("privacy: no network; any host added must be named in the statement", () => {
  assert.match(About.PRIVACY, /No network access, no accounts and no telemetry/)
  assert.ok(About.PRIVACY.includes("~/.local/state/omarchy-dopewars/save.json"))
  assert.ok(read("Service.qml").includes('"/.local/state/omarchy-dopewars"') && read("Service.qml").includes('"/save.json"'))
  assert.ok(About.PRIVACY.includes("~/.config/omarchy/shell.json"))
  const files = fs.readdirSync(ROOT).filter((f) => /\.(qml|js|sh|py)$/.test(f))
  assert.ok(files.includes("Service.qml") && files.includes("Game.js"))
  for (const f of files) {
    const text = read(f)
    for (const m of text.matchAll(/\b(?:https?|wss?|ftp):\/\/([^/"'`\s$)]+)/g))
      assert.ok(About.PRIVACY.includes(m[1]), `${f} talks to ${m[1]}, which the privacy statement does not name`)
    for (const api of ["XMLHttpRequest", "WebSocket", "Socket {", "NetworkAccess", "curl", "wget", "fetch("])
      assert.ok(!text.includes(api), `${f} uses ${api}; update the privacy statement and this test`)
  }
})

if (failures) { console.error(failures + " failed"); process.exit(1) }
console.log("about tests passed")
