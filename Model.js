.pragma library

var ICON_ON = "󰍬"        // md-microphone
var ICON_OFF = "󰍭"       // md-microphone_off
var ICON_WIZARD = "󰁨"    // md-auto_fix
var ICON_QUIET = "󰖁"     // md-volume_off
var ICON_SPEECH = "󰗋"    // md-account_voice
var ICON_TYPING = "󰌌"    // md-keyboard
var ICON_RESTORE = "󰦛"   // md-restore
var ICON_PLAY = "󰐊"      // md-play
var ICON_STOP = "󰓛"      // md-stop
var ICON_HEADPHONES = "󰋋" // md-headphones

// The chain's stages in signal order: the switch that bypasses each, and its
// sliders. Keys and ranges match the helper's SETTINGS table. A stage opens to
// its everyday controls; `advanced` ones wait behind "More".
var STAGES = [
  { id: "input", title: "INPUT", toggle: "", controls: [
    { key: "gain", label: "Gain", unit: "dB", min: -12, max: 24, step: 0.5 } ] },
  { id: "hpf", title: "HIGH-PASS", toggle: "hpf.enabled", controls: [
    { key: "hpf.freq", label: "Frequency", unit: "Hz", min: 20, max: 300, step: 5 } ] },
  { id: "suppress", title: "NOISE SUPPRESSION", toggle: "suppress.enabled", controls: [
    { key: "suppress.strength", label: "Strength", unit: "%", min: 0, max: 100, step: 1 },
    { key: "suppress.vad", label: "Voice detection", unit: "%", min: 0, max: 95, step: 1, advanced: true } ] },
  { id: "gate", title: "NOISE GATE", toggle: "gate.enabled", controls: [
    { key: "gate.threshold", label: "Threshold", unit: "dB", min: -90, max: -10, step: 0.5 },
    { key: "gate.range", label: "Range", unit: "dB", min: -80, max: 0, step: 1, advanced: true },
    { key: "gate.hold", label: "Hold", unit: "ms", min: 0, max: 500, step: 5, advanced: true },
    { key: "gate.release", label: "Release", unit: "ms", min: 5, max: 1000, step: 5, advanced: true } ] },
  { id: "tone", title: "TONE", toggle: "tone.enabled", controls: [
    { key: "tone.nasal.cut", label: "Nasal cut", unit: "dB", min: -12, max: 0, step: 0.5 },
    { key: "tone.box.cut", label: "Boxiness cut", unit: "dB", min: -12, max: 0, step: 0.5 },
    { key: "tone.presence.gain", label: "Presence", unit: "dB", min: -6, max: 6, step: 0.5 },
    { key: "tone.air.gain", label: "Air", unit: "dB", min: -6, max: 6, step: 0.5 },
    { key: "tone.nasal.freq", label: "Nasal frequency", unit: "Hz", min: 600, max: 2000, step: 10, advanced: true },
    { key: "tone.nasal.q", label: "Nasal width (Q)", unit: "", min: 0.5, max: 10, step: 0.1, advanced: true },
    { key: "tone.box.freq", label: "Boxiness frequency", unit: "Hz", min: 200, max: 800, step: 10, advanced: true },
    { key: "tone.box.q", label: "Boxiness width (Q)", unit: "", min: 0.5, max: 10, step: 0.1, advanced: true },
    { key: "tone.presence.freq", label: "Presence frequency", unit: "Hz", min: 2000, max: 6000, step: 100, advanced: true },
    { key: "tone.air.freq", label: "Air frequency", unit: "Hz", min: 6000, max: 16000, step: 250, advanced: true } ] },
  { id: "comp", title: "COMPRESSOR", toggle: "comp.enabled", controls: [
    { key: "comp.threshold", label: "Threshold", unit: "dB", min: -60, max: 0, step: 0.5 },
    { key: "comp.makeup", label: "Makeup", unit: "dB", min: 0, max: 24, step: 0.5 },
    { key: "comp.ratio", label: "Ratio", unit: ":1", min: 1, max: 20, step: 0.5, advanced: true },
    { key: "comp.attack", label: "Attack", unit: "ms", min: 0, max: 200, step: 1, advanced: true },
    { key: "comp.release", label: "Release", unit: "ms", min: 10, max: 1000, step: 5, advanced: true } ] },
  { id: "limit", title: "LIMITER", toggle: "limit.enabled", controls: [
    { key: "limit.ceiling", label: "Ceiling", unit: "dB", min: -24, max: 0, step: 0.5 } ] }
]

function hasAdvanced(spec) {
  if (!spec) return false
  for (var i = 0; i < spec.controls.length; i++) if (spec.controls[i].advanced === true) return true
  return false
}

// One line saying what a closed stage is doing. `get(key)` reads a setting.
function stageSummary(spec, get) {
  if (!spec) return ""
  if (spec.toggle && get(spec.toggle) !== true) return "off"
  var f = function(key, unit) { return formatValue(get(key), unit) }
  switch (spec.id) {
  case "input": return f("gain", "dB")
  case "hpf": return f("hpf.freq", "Hz")
  case "suppress": return f("suppress.strength", "%")
  case "gate": return f("gate.threshold", "dB")
  case "comp": return f("comp.threshold", "dB") + ", " + f("comp.ratio", ":1")
  case "limit": return f("limit.ceiling", "dB")
  case "tone":
    var parts = []
    if (Number(get("tone.nasal.cut")) < 0) parts.push("nasal " + f("tone.nasal.cut", "dB") + " @ " + hz(get("tone.nasal.freq")))
    if (Number(get("tone.box.cut")) < 0) parts.push("box " + f("tone.box.cut", "dB"))
    if (Number(get("tone.presence.gain")) !== 0) parts.push("presence " + f("tone.presence.gain", "dB"))
    if (Number(get("tone.air.gain")) !== 0) parts.push("air " + f("tone.air.gain", "dB"))
    return parts.length ? parts.join(", ") : "flat"
  }
  return ""
}

function hz(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  return n >= 1000 ? (n / 1000).toFixed(n % 1000 === 0 ? 0 : 1) + " kHz" : Math.round(n) + " Hz"
}

var PHASES = [
  { id: "quiet", title: "Stay quiet", seconds: 8, icon: ICON_QUIET,
    text: "Sit at the mic as you normally would and don't make a sound. This measures your room's background noise." },
  { id: "speech", title: "Talk normally", seconds: 12, icon: ICON_SPEECH,
    text: "Talk at your natural volume and distance, as you would on a call. Read this aloud if you like:",
    sample: "I'm setting up my microphone so I sound clear on calls. The quick brown fox jumps over the lazy dog, and the background noise should stay out of it." },
  { id: "typing", title: "Type, without talking", seconds: 10, icon: ICON_TYPING, typing: true,
    text: "Type in the box below as you normally would, and stay silent. This measures how much keyboard noise gets through.",
    sample: "Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump!" }
]

var LABELS = {
  "gain": "Input gain",
  "suppress.enabled": "Noise suppression",
  "suppress.strength": "Suppression strength",
  "suppress.vad": "Voice detection",
  "gate.enabled": "Gate",
  "gate.threshold": "Gate threshold",
  "gate.range": "Gate range",
  "comp.enabled": "Compressor",
  "comp.threshold": "Compressor threshold",
  "comp.ratio": "Compressor ratio",
  "comp.makeup": "Makeup gain",
  "limit.enabled": "Limiter",
  "limit.ceiling": "Limiter ceiling"
}

var UNITS = {
  "gain": "dB", "suppress.strength": "%", "suppress.vad": "%", "gate.threshold": "dB",
  "gate.range": "dB", "comp.threshold": "dB", "comp.ratio": ":1", "comp.makeup": "dB",
  "limit.ceiling": "dB"
}

var MEASURED = [
  { key: "floorRaw", label: "Room noise" },
  { key: "floorAfterSuppression", label: "  after suppression" },
  { key: "speech", label: "Your speech" },
  { key: "speechPeak", label: "Speech peaks" },
  { key: "typing", label: "Typing" },
  { key: "typingAfterSuppression", label: "  after suppression" }
]

function formatValue(value, unit) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  var whole = unit === "%" || unit === "ms" || unit === "Hz" || Math.abs(n) >= 100
  var text = whole ? String(Math.round(n)) : n.toFixed(1).replace(/\.0$/, "")
  if (unit === ":1") return text + ":1"
  if (unit === "") return text
  if (unit === "dB" && n > 0) text = "+" + text
  return unit === "%" ? text + "%" : text + " " + unit
}

// Level meters span -72 dBFS (empty) to 0 dBFS (full).
function meter(db) {
  var n = Number(db)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(1, (n + 72) / 72))
}

function dbText(db) {
  var n = Number(db)
  return isFinite(n) && n > -119 ? Math.round(n) + " dBFS" : "silence"
}

function phaseIcon(id) {
  for (var i = 0; i < PHASES.length; i++) if (PHASES[i].id === id) return PHASES[i].icon
  return ICON_WIZARD
}

function phaseSummary(id, r) {
  if (!r || !r.raw || !r.fx) return ""
  if (id === "quiet") return "Room noise " + dbText(r.raw.p50) + ", " + dbText(r.fx.p90) + " after suppression."
  if (id === "speech") return "Speech up to " + dbText(r.raw.p90) + ", peaks " + dbText(r.raw.max) + "."
  return "Typing up to " + dbText(r.raw.p95) + ", " + dbText(r.fx.p95) + " after suppression."
}

// The suggestion as rows of what would change, from what to what. Settings
// that already match are left out, so the list is exactly what Apply does.
function changes(suggested, current) {
  var rows = []
  if (!suggested) return rows
  for (var key in suggested) {
    var to = suggested[key]
    var from = current ? current[key] : undefined
    if (typeof to === "boolean") {
      if (from === to) continue
      rows.push({ label: LABELS[key] || key, from: from === undefined ? "—" : (from ? "on" : "off"), to: to ? "on" : "off" })
    } else {
      if (from !== undefined && Math.abs(Number(from) - Number(to)) < 0.05) continue
      var unit = UNITS[key] || ""
      rows.push({ label: LABELS[key] || key, from: from === undefined ? "—" : formatValue(from, unit), to: formatValue(to, unit) })
    }
  }
  return rows
}

function tooltip(status) {
  if (!status) return "Mic FX — loading…"
  var device = status.device ? (status.device.description || status.device.name || "no device") : "no device"
  if (!status.present) return "Mic FX — off\n" + device
  return "Mic FX — on" + (status.isDefault ? " (default input)" : " (not the default input)") + "\n" + device
}
