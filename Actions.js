.pragma library

// Menú de acciones (Ctrl+.): qué acciones aplican a un clip según su tipo y
// las transformaciones de texto. Puro, sin imports, para que corra igual en
// QML y en node (tests/test-actions.mjs). Los textos visibles son claves
// "action.<id>" de lang/*.js; aquí solo ids e iconos.

var ICONS = {
  paste: "󰆒", copy: "󰆏", edit: "󰏫", note: "󰎚", pin: "󰐃", unpin: "󰐄", delete: "󰆴",
  open: "󰏌", openLink: "󰖟", copyDomain: "󰇧",
  copyHex: "󰏘", copyRgb: "󰏘", copyHsl: "󰏘",
  copyOcr: "󰈙", copyQr: "󰐲", copyPath: "󰉋", copyPaths: "󰉋",
  jsonPretty: "󰘦", jsonMinify: "󰘦",
  trim: "󰉣", upper: "󰬶", lower: "󰬵", title: "󰊄",
  sortLines: "󰒺", dedupeLines: "󰆴", removeEmptyLines: "󰉣", joinLines: "󰘞"
}

// Acciones que transforman el texto: abren el editor con el resultado como
// borrador (se guarda con Ctrl+Enter o se descarta con Esc).
var TRANSFORMS = ["jsonPretty", "jsonMinify", "trim", "upper", "lower", "title",
  "sortLines", "dedupeLines", "removeEmptyLines", "joinLines"]

function isTransform(id) { return TRANSFORMS.indexOf(id) >= 0 }

// entry: el clip; derived: su tipo (Classify.deriveType). Devuelve ids en el
// orden en que se muestran: lo propio del tipo primero, lo común al final.
function listFor(entry, derived) {
  if (!entry) return []
  var out = []
  if (entry.type === "image") {
    if (entry.ocr) out.push("copyOcr")
    if (entry.qr) out.push("copyQr")
    out.push("open", "copyPath")
  } else if (entry.type === "files") {
    out.push("open", "copyPaths")
  } else {
    if (derived === "link") out.push("openLink", "copyDomain")
    if (derived === "color") out.push("copyHex", "copyRgb", "copyHsl")
    if (derived === "json") out.push("jsonPretty", "jsonMinify")
    out.push("edit")
    var multiline = String(entry.text || "").indexOf("\n") >= 0
    out.push("trim", "upper", "lower", "title")
    if (multiline) out.push("sortLines", "dedupeLines", "removeEmptyLines", "joinLines")
  }
  out.push("paste", "copy", "note", entry.pinned ? "unpin" : "pin", "delete")
  return out
}

function lines(text) { return String(text).split("\n") }

// Devuelve el texto transformado, o null si no aplica (p. ej. JSON inválido).
function transform(id, text) {
  var s = String(text === undefined || text === null ? "" : text)
  switch (id) {
  case "trim":
    return lines(s).map(function(l) { return l.replace(/\s+$/, "") }).join("\n").trim()
  case "upper": return s.toUpperCase()
  case "lower": return s.toLowerCase()
  case "title":
    return s.toLowerCase().replace(/(^|[\s\-_/(\[{"'¿¡])([^\s])/g, function(m, sep, ch) { return sep + ch.toUpperCase() })
  case "sortLines":
    return lines(s).slice().sort(function(a, b) {
      var x = a.toLowerCase(), y = b.toLowerCase()
      return x < y ? -1 : x > y ? 1 : 0
    }).join("\n")
  case "dedupeLines":
    var seen = {}
    return lines(s).filter(function(l) {
      if (seen.hasOwnProperty(l)) return false
      seen[l] = true
      return true
    }).join("\n")
  case "removeEmptyLines":
    return lines(s).filter(function(l) { return l.trim() !== "" }).join("\n")
  case "joinLines":
    return lines(s).map(function(l) { return l.trim() }).filter(function(l) { return l !== "" }).join(" ")
  case "jsonPretty":
  case "jsonMinify":
    try {
      var v = JSON.parse(s)
      return id === "jsonPretty" ? JSON.stringify(v, null, 2) : JSON.stringify(v)
    } catch (e) {
      return null
    }
  }
  return null
}

// Filtro del menú: todas las palabras deben aparecer en la etiqueta.
function matches(label, query) {
  var q = String(query || "").toLowerCase().trim()
  if (!q) return true
  var l = String(label || "").toLowerCase()
  var parts = q.split(/\s+/)
  for (var i = 0; i < parts.length; i++) if (l.indexOf(parts[i]) < 0) return false
  return true
}
