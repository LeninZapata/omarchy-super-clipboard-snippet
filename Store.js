.pragma library

// History store operations: normalization, dedup, pins, pruning.
// Pure ES5 — runs in QML (.pragma library) and node (tests).

var DEFAULT_LIMIT = 1500

// FNV-1a 32-bit, hex. Used for stable entry ids.
function hash32(s) {
  var h = 0x811c9dc5
  s = String(s || "")
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = (h + (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24)) >>> 0
  }
  return ("0000000" + h.toString(16)).slice(-8)
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  if (entry.type === "files") return "files:" + (entry.paths || []).join("\n")
  return "text:" + String(entry.text || "")
}

function entryId(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "img:" + hash32(String(entry.path || ""))
  if (entry.type === "files") return "files:" + hash32((entry.paths || []).join("\n"))
  return "txt:" + hash32(String(entry.text || "")) + ":" + String(entry.text || "").length
}

// Validate + fill defaults. Returns null for entries that should be dropped.
function normalize(value, now) {
  if (!value || typeof value !== "object") return null
  var type = String(value.type || "")
  var out = null

  if (type === "text") {
    var text = String(value.text || "")
    if (!text.trim()) return null
    out = { type: "text", text: text }
  } else if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    out = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.w) out.w = Number(value.w)
    if (value.h) out.h = Number(value.h)
    if (value.qr) out.qr = String(value.qr)
    if (value.ocr) out.ocr = String(value.ocr)
  } else if (type === "files") {
    var paths = Array.isArray(value.paths) ? value.paths.filter(function(p) { return !!p }) : []
    if (paths.length === 0) return null
    out = { type: "files", paths: paths }
  } else {
    return null
  }

  var ts = Number(value.ts)
  out.ts = isFinite(ts) && ts > 0 ? Math.floor(ts) : (now || 0)
  var bytes = Number(value.bytes)
  out.bytes = isFinite(bytes) && bytes >= 0 ? Math.floor(bytes) : 0
  out.app = String(value.app || "")
  out.id = String(value.id || entryId(out))
  var uses = Number(value.uses)
  out.uses = isFinite(uses) && uses > 0 ? Math.floor(uses) : 0
  // Nota del usuario sobre el clip (Ctrl+M): se ve en el preview y se busca.
  if (value.note && String(value.note).trim()) out.note = String(value.note).slice(0, MAX_NOTE)
  if (value.pinned) {
    out.pinned = true
    // Cuándo se fijó: da a cada pin un número estable (Ctrl+1…9) que no
    // cambia al pegarlo ni al recopiarlo. Los pines sin fecha (anteriores) van primero.
    var pinnedAt = Number(value.pinnedAt)
    if (isFinite(pinnedAt) && pinnedAt > 0) out.pinnedAt = Math.floor(pinnedAt)
  }
  return out
}

function parseHistory(raw, now) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next
    for (var i = 0; i < parsed.length; i++) {
      var e = normalize(parsed[i], now)
      if (e) next.push(e)
    }
    return next
  } catch (err) {
    return []
  }
}

// Add (or bump) an entry; newest first. Keeps pin state and usage count of
// the existing copy when the same content is copied again. Does NOT truncate
// to the limit: the caller prunes via prune() so evicted image blobs can be
// garbage-collected (truncating here would leak them).
function addEntry(history, entry, now) {
  var normalized = normalize(entry, now)
  if (!normalized) return Array.isArray(history) ? history.slice() : []

  var key = entryKey(normalized)
  var next = [normalized]
  var values = Array.isArray(history) ? history : []
  for (var i = 0; i < values.length; i++) {
    var existing = normalize(values[i], now)
    if (!existing) continue
    if (entryKey(existing) === key) {
      // Re-copy of existing content: keep its pin state and usage count.
      if (existing.pinned) {
        normalized.pinned = true
        if (existing.pinnedAt) normalized.pinnedAt = existing.pinnedAt
      }
      if (existing.uses > 0) normalized.uses = existing.uses
      if (existing.note && !normalized.note) normalized.note = existing.note
      // Keep expensive derived data (decoded QR, OCR) across re-captures.
      if (existing.qr && !normalized.qr) normalized.qr = existing.qr
      if (existing.ocr && !normalized.ocr) normalized.ocr = existing.ocr
      continue
    }
    next.push(existing)
  }
  return next
}

function findById(history, id) {
  var values = Array.isArray(history) ? history : []
  for (var i = 0; i < values.length; i++) {
    if (values[i] && values[i].id === id) return values[i]
  }
  return null
}

function removeById(history, id) {
  var values = Array.isArray(history) ? history : []
  var next = []
  for (var i = 0; i < values.length; i++) {
    if (values[i] && values[i].id === id) continue
    next.push(values[i])
  }
  return next
}

function togglePin(history, id, now) {
  var values = Array.isArray(history) ? history : []
  var entry = findById(values, id)
  if (!entry) return values
  if (entry.pinned) {
    delete entry.pinned
    delete entry.pinnedAt
  } else {
    entry.pinned = true
    entry.pinnedAt = now || Math.floor(Date.now() / 1000)
  }
  return values
}

// Edita el texto de un clip (F2 / Ctrl+E). Solo clips de texto. El id sale del
// contenido, así que cambia; si el nuevo texto ya existía en otro clip, se
// fusionan (queda uno, y fijado si cualquiera de los dos lo estaba).
// Devuelve { history, id } con el id nuevo para que la UI siga al clip.
function updateText(history, id, text, now) {
  var values = Array.isArray(history) ? history : []
  var entry = findById(values, id)
  var value = String(text === undefined || text === null ? "" : text)
  if (!entry || entry.type !== "text" || !value.trim() || value === entry.text)
    return { history: values, id: id }

  var edited = {}
  for (var k in entry) edited[k] = entry[k]
  edited.text = value
  edited.bytes = unescape(encodeURIComponent(value)).length
  edited.id = entryId(edited)
  var key = entryKey(edited)

  var next = []
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (e === entry) { next.push(edited); continue }
    if (e && entryKey(e) === key) {
      if (e.pinned && !edited.pinned) {
        edited.pinned = true
        if (e.pinnedAt) edited.pinnedAt = e.pinnedAt
      }
      edited.uses = (Number(edited.uses) || 0) + (Number(e.uses) || 0)
      if (e.note && !edited.note) edited.note = e.note
      continue
    }
    next.push(e)
  }
  return { history: next, id: edited.id }
}

var MAX_NOTE = 2000

// Pone (o quita, si queda vacía) la nota de un clip. Cualquier tipo de clip.
function setNote(history, id, note) {
  var values = Array.isArray(history) ? history : []
  var entry = findById(values, id)
  if (!entry) return values
  var value = String(note === undefined || note === null ? "" : note).trim()
  if (value) entry.note = value.slice(0, MAX_NOTE)
  else delete entry.note
  return values
}

// Ids de los pines en su orden fijo: el primero que se fijó es el 1. Es el
// orden del grupo "Pinned" y el de Ctrl+1…9, con o sin búsqueda activa.
function pinOrder(history) {
  var values = Array.isArray(history) ? history : []
  var pins = []
  for (var i = 0; i < values.length; i++) {
    if (values[i] && values[i].pinned) pins.push({ id: values[i].id, at: Number(values[i].pinnedAt) || 0, pos: i })
  }
  pins.sort(function(a, b) {
    if (a.at && b.at && a.at !== b.at) return a.at - b.at
    // Sin fecha = fijado antes de que existiera pinnedAt, o sea más antiguo
    // que cualquiera con fecha: va primero para no robarle su número.
    if (!a.at !== !b.at) return a.at ? 1 : -1
    return a.pos - b.pos
  })
  return pins.map(function(p) { return p.id })
}

// Parte los resultados en dos grupos: primero los fijados (en su orden fijo)
// y luego el historial (en el orden que ya traía la búsqueda).
function groupPinned(results, order) {
  var rank = {}
  for (var i = 0; i < order.length; i++) rank[order[i]] = i
  var pinned = []
  var rest = []
  for (var j = 0; j < results.length; j++) {
    var id = results[j].row.entry.id
    if (results[j].row.entry.pinned && rank[id] !== undefined) pinned.push(results[j])
    else rest.push(results[j])
  }
  pinned.sort(function(a, b) { return rank[a.row.entry.id] - rank[b.row.entry.id] })
  return { results: pinned.concat(rest), pinnedCount: pinned.length }
}

function touch(history, id, now) {
  var values = Array.isArray(history) ? history : []
  var entry = findById(values, id)
  if (!entry) return values
  entry.uses = (Number(entry.uses) || 0) + 1
  entry.ts = now || entry.ts
  // Move to front like a fresh copy would.
  var next = [entry]
  for (var i = 0; i < values.length; i++) {
    if (values[i] !== entry) next.push(values[i])
  }
  return next
}

// Enforce the limit. Returns { entries, droppedImagePaths } so the caller can
// garbage-collect image blobs.
function prune(history, limit) {
  var values = Array.isArray(history) ? history : []
  var max = limit === undefined || limit === null ? DEFAULT_LIMIT : Number(limit)
  if (isNaN(max) || max < 1) max = DEFAULT_LIMIT
  if (values.length <= max) return { entries: values, droppedImagePaths: [] }

  // Los pines no cuentan para el límite y nunca se podan: son el grupo fijo de
  // arriba y su número (Ctrl+N) no puede desaparecer por copiar mucho.
  var kept = []
  var droppedImagePaths = []
  var unpinned = 0
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (!e) continue
    if (e.pinned || unpinned < max) {
      if (!e.pinned) unpinned++
      kept.push(e)
    } else if (e.type === "image" && e.path) {
      droppedImagePaths.push(e.path)
    }
  }
  return { entries: kept, droppedImagePaths: droppedImagePaths }
}

// Límites de peso (settings): imágenes en disco y tamaño del history.json.
// Recorre de nuevo a viejo y poda lo más viejo no fijado que ya no cabe;
// los pines cuentan para el total pero nunca se podan. Un límite <= 0 no aplica.
function pruneBySize(history, maxImageBytes, maxHistoryBytes) {
  var values = Array.isArray(history) ? history : []
  var kept = []
  var droppedImagePaths = []
  var imageUsed = 0
  var historyUsed = 0
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (!e) continue
    var imageBytes = e.type === "image" ? (Number(e.bytes) || 0) : 0
    var entryBytes = JSON.stringify(e).length
    var fits = (!(maxImageBytes > 0) || imageUsed + imageBytes <= maxImageBytes)
            && (!(maxHistoryBytes > 0) || historyUsed + entryBytes <= maxHistoryBytes)
    if (e.pinned || fits) {
      imageUsed += imageBytes
      historyUsed += entryBytes
      kept.push(e)
    } else if (e.type === "image" && e.path) {
      droppedImagePaths.push(e.path)
    }
  }
  return { entries: kept, droppedImagePaths: droppedImagePaths }
}

// Retention: drop entries older than maxAgeSeconds (-1 = keep forever).
// Pinned entries are exempt — pins are favorites; delete them explicitly.
// Returns { entries, droppedImagePaths } like prune().
function pruneByAge(history, maxAgeSeconds, now) {
  var values = Array.isArray(history) ? history : []
  if (maxAgeSeconds === undefined || maxAgeSeconds === null || maxAgeSeconds < 0)
    return { entries: values, droppedImagePaths: [] }
  var cutoff = now - maxAgeSeconds
  var kept = []
  var droppedImagePaths = []
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (!e) continue
    if ((Number(e.ts) || 0) < cutoff && !e.pinned) {
      if (e.type === "image" && e.path) droppedImagePaths.push(e.path)
      continue
    }
    kept.push(e)
  }
  return { entries: kept, droppedImagePaths: droppedImagePaths }
}

// Parse this plugin's settings from the shell.json contents. Every key is
// optional; unknown keys are ignored. Reads only the plugins[] entry whose
// id matches.
// Settings propios del plugin: ~/.config/omarchy/super-clipboard-snippet/settings.json,
// un objeto plano. Cada clave tiene su default y su rango; lo inválido cae al default.
var SETTINGS_SPEC = {
  language: { type: "string", def: "en" }, // lang/<language>.js; lo desconocido cae al inglés
  size: { type: "string", def: "normal" }, // "normal" | "compact"
  position: { type: "string", def: "center" }, // "center" | "cursor"
  // Atajos globales que registra el plugin en Hyprland (vacío = no registrar):
  // ids tipo "ctrl+shift+v"; Clipboard.qml los convierte en "CTRL + SHIFT + V".
  openShortcut: { type: "string", def: "" },
  quickShortcut: { type: "string", def: "" },
  closeOnClickOutside: { type: "bool", def: true },
  confirmDelete: { type: "bool", def: false },
  historyLimit: { type: "int", def: 500, min: 50, max: 100000 },
  maxAgeDays: { type: "int", def: 7, min: 0, max: 3650 },
  maxImageCacheMB: { type: "int", def: 256, min: 16, max: 4096 },
  maxHistoryMB: { type: "int", def: 8, min: 1, max: 256 },
  maxRows: { type: "int", def: 200, min: 10, max: 1000 },
  qrDecode: { type: "bool", def: true },
  ocr: { type: "bool", def: true },
  ocrLang: { type: "string", def: "eng" }
}

function defaultSettings() {
  var out = {}
  for (var k in SETTINGS_SPEC) out[k] = SETTINGS_SPEC[k].def
  return out
}

function normalizeSettings(value) {
  var out = defaultSettings()
  if (!value || typeof value !== "object" || Array.isArray(value)) return out
  for (var k in SETTINGS_SPEC) {
    var spec = SETTINGS_SPEC[k]
    var v = value[k]
    if (spec.type === "bool") {
      if (typeof v === "boolean") out[k] = v
    } else if (spec.type === "int") {
      var n = Number(v)
      if (v !== null && v !== "" && isFinite(n)) out[k] = Math.max(spec.min, Math.min(spec.max, Math.floor(n)))
    } else if (typeof v === "string" && /^[a-z_]+(\+[a-z_]+)*$/.test(v)) {
      out[k] = v
    }
  }
  return out
}

function parseSettings(raw) {
  try { return normalizeSettings(JSON.parse(String(raw || "{}"))) } catch (e) { return defaultSettings() }
}

function serializeSettings(settings) {
  return JSON.stringify(normalizeSettings(settings), null, 2) + "\n"
}

// Build the search-row context Fuzzy.searchRows expects.
function buildRow(entry, derivedType, now) {
  var content = ""
  if (entry.type === "image") {
    content = fileLabel(entry.path) + " " + String(entry.mime || "")
    if (entry.qr) content += " " + String(entry.qr).slice(0, 500)
    // OCR text makes screenshots searchable like any text clip.
    if (entry.ocr) content += " " + String(entry.ocr).slice(0, 4000)
  } else if (entry.type === "files") {
    content = (entry.paths || []).join(" ")
  } else {
    // Cap haystack size for speed; deep content is still previewable.
    content = String(entry.text || "").slice(0, 4000)
  }
  if (entry.note) content += " " + String(entry.note)
  return {
    entry: entry,
    content: content,
    app: String(entry.app || ""),
    type: derivedType,
    ts: Number(entry.ts) || 0,
    pinned: !!entry.pinned,
    uses: Number(entry.uses) || 0,
    bytes: Number(entry.bytes) || 0
  }
}

function fileLabel(p) {
  var s = String(p || "")
  var idx = s.lastIndexOf("/")
  return idx === -1 ? s : s.slice(idx + 1)
}
