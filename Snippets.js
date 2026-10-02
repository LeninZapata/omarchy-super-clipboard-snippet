.pragma library

// Snippets: plantillas con nombre, slug (código corto para buscarlas, p. ej.
// "__target_banco_guayaquil") y texto (Markdown) con variables de fecha/hora.
// Puro, sin imports: corre igual en QML y en node (tests/test-snippets.mjs).
// Los textos visibles salen de lang/*.js (`L`); sin `L`, inglés.

var MAX_BODY = 200000

function makeId(now) {
  return "snp:" + Math.floor(Number(now) || Date.now()).toString(36) + Math.random().toString(36).slice(2, 7)
}

// Slug: minúsculas, sin espacios; se permiten letras, números, _ - . y /.
function normalizeSlug(s) {
  return String(s || "").trim().toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_\-./]/g, "")
}

function normalize(value, now) {
  if (!value || typeof value !== "object") return null
  var body = String(value.body || "")
  var name = String(value.name || "").trim()
  if (!body.trim() && !name) return null
  var out = {
    id: String(value.id || makeId(now)),
    name: name.slice(0, 200),
    slug: normalizeSlug(value.slug).slice(0, 120),
    body: body.slice(0, MAX_BODY)
  }
  var c = Number(value.createdAt), u = Number(value.updatedAt)
  out.createdAt = isFinite(c) && c > 0 ? Math.floor(c) : Math.floor(Number(now) || 0)
  out.updatedAt = isFinite(u) && u > 0 ? Math.floor(u) : out.createdAt
  return out
}

function parseList(raw, now) {
  var parsed
  try { parsed = JSON.parse(String(raw || "[]")) } catch (e) { return [] }
  var list = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.snippets) ? parsed.snippets : [])
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var s = normalize(list[i], now)
    if (!s || seen[s.id]) continue
    seen[s.id] = true
    out.push(s)
  }
  return out
}

function serialize(list) {
  return JSON.stringify(list, null, 1) + "\n"
}

function findById(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

// Inserta o reemplaza (por id). Devuelve { list, id }.
function upsert(list, snippet, now) {
  var s = normalize(snippet, now)
  if (!s) return { list: list, id: "" }
  s.updatedAt = Math.floor(Number(now) || s.updatedAt)
  var next = []
  var replaced = false
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === s.id) {
      s.createdAt = list[i].createdAt
      next.push(s)
      replaced = true
    } else {
      next.push(list[i])
    }
  }
  if (!replaced) next.unshift(s)
  return { list: next, id: s.id }
}

function remove(list, id) {
  return list.filter(function(s) { return s.id !== id })
}

// ¿Otro snippet ya usa este slug? (para avisar en el editor)
function slugTaken(list, slug, exceptId) {
  var n = normalizeSlug(slug)
  if (!n) return false
  for (var i = 0; i < list.length; i++) if (list[i].slug === n && list[i].id !== exceptId) return true
  return false
}

// Importar: los de `incoming` reemplazan a los del mismo id o slug; el resto se suma.
function merge(list, incoming, now) {
  var next = list.slice()
  var added = 0, updated = 0
  for (var i = 0; i < incoming.length; i++) {
    var s = normalize(incoming[i], now)
    if (!s) continue
    var at = -1
    for (var j = 0; j < next.length; j++) {
      if (next[j].id === s.id || (s.slug && next[j].slug === s.slug)) { at = j; break }
    }
    if (at >= 0) { s.id = next[at].id; next[at] = s; updated++ }
    else { next.push(s); added++ }
  }
  return { list: next, added: added, updated: updated }
}

// ---------------------------------------------------------------- búsqueda
// Solo por slug y nombre. Todas las palabras deben coincidir; el slug pesa más.

function subsequence(needle, hay) {
  var j = 0
  for (var i = 0; i < hay.length && j < needle.length; i++) if (hay[i] === needle[j]) j++
  return j === needle.length
}

function scoreTerm(term, s) {
  var slug = s.slug, name = s.name.toLowerCase()
  if (slug === term) return 1000
  if (slug && slug.indexOf(term) === 0) return 800
  if (slug && slug.indexOf(term) >= 0) return 600
  if (name.indexOf(term) === 0) return 500
  if (name.indexOf(term) >= 0) return 400
  if (slug && subsequence(term, slug)) return 200
  if (subsequence(term, name)) return 100
  return 0
}

function search(list, query) {
  var q = String(query || "").toLowerCase().trim()
  if (!q) return list.slice().sort(function(a, b) { return a.name.localeCompare(b.name) })
  var terms = q.split(/\s+/)
  var hits = []
  for (var i = 0; i < list.length; i++) {
    var total = 0
    for (var t = 0; t < terms.length; t++) {
      var sc = scoreTerm(terms[t], list[i])
      if (!sc) { total = 0; break }
      total += sc
    }
    if (total > 0) hits.push({ s: list[i], score: total })
  }
  hits.sort(function(a, b) { return b.score - a.score || a.s.name.localeCompare(b.s.name) })
  return hits.map(function(h) { return h.s })
}

// ---------------------------------------------------------------- variables
// {date_short} {date_medium} {date_long} {date_iso} {time} {time_12}
// {time_seconds} {weekday} {month} {day} {year} {datetime} {clipboard}.
// Las fechas salen en el idioma de L. Una variable desconocida se deja tal cual.

var VARIABLES = ["date_short", "date_medium", "date_long", "date_iso", "datetime",
  "time", "time_12", "time_seconds", "weekday", "month", "day", "year", "clipboard"]

function str(L, key, fallback) { return L && L[key] !== undefined ? String(L[key]) : fallback }
function pad2(n) { return n < 10 ? "0" + n : "" + n }
function fill(template, args) {
  return String(template).replace(/\{(\w+)\}/g, function(m, k) { return args[k] !== undefined ? String(args[k]) : m })
}

var EN_MONTHS = "January,February,March,April,May,June,July,August,September,October,November,December"
var EN_MONTHS_SHORT = "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec"
var EN_WEEKDAYS = "Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday"

function parts(d, L) {
  var h = d.getHours()
  var h12 = h % 12 === 0 ? 12 : h % 12
  return {
    d: d.getDate(), dd: pad2(d.getDate()), mm: pad2(d.getMonth() + 1), yyyy: d.getFullYear(),
    month: str(L, "snip.months.long", EN_MONTHS).split(",")[d.getMonth()],
    mon: str(L, "months", EN_MONTHS_SHORT).split(",")[d.getMonth()],
    weekday: str(L, "snip.weekdays.long", EN_WEEKDAYS).split(",")[d.getDay()],
    HH: pad2(h), MM: pad2(d.getMinutes()), SS: pad2(d.getSeconds()),
    h12: h12, ampm: h < 12 ? "AM" : "PM"
  }
}

function value(name, d, L, clipboard) {
  var p = parts(d, L)
  switch (name) {
  case "date_short": return fill(str(L, "snip.fmt.dateShort", "{mm}/{dd}/{yyyy}"), p)
  case "date_medium": return fill(str(L, "snip.fmt.dateMedium", "{mon} {d}, {yyyy}"), p)
  case "date_long": return fill(str(L, "snip.fmt.dateLong", "{weekday}, {month} {d}, {yyyy}"), p)
  case "date_iso": return p.yyyy + "-" + p.mm + "-" + p.dd
  case "datetime": return fill(str(L, "snip.fmt.dateMedium", "{mon} {d}, {yyyy}"), p) + " " + p.HH + ":" + p.MM
  case "time": return p.HH + ":" + p.MM
  case "time_12": return p.h12 + ":" + p.MM + " " + p.ampm
  case "time_seconds": return p.HH + ":" + p.MM + ":" + p.SS
  case "weekday": return p.weekday
  case "month": return p.month
  case "day": return String(p.d)
  case "year": return String(p.yyyy)
  case "clipboard": return String(clipboard || "")
  }
  return null
}

// ctx: { now: Date | ms, L: diccionario de idioma, clipboard: texto del último clip }
function render(body, ctx) {
  var c = ctx || {}
  var d = c.now instanceof Date ? c.now : new Date(c.now === undefined ? Date.now() : c.now)
  return String(body || "").replace(/\{([a-z_0-9]+)\}/g, function(m, name) {
    var v = value(name, d, c.L, c.clipboard)
    return v === null ? m : v
  })
}
