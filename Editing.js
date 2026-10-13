.pragma library
// Plain text editing logic for PlainEdit.qml: cursor, selection, word moves,
// deletion and line wrapping. No native Qt text field involved.
//
// Por qué existe: un TextInput/TextEdit editable de Qt vuelve a leer el texto
// del portapapeles ajeno en cada cambio (canPaste), sin tope de tamaño ni de
// tiempo, y el shell es compartido. El plugin dibuja sus propios campos y esta
// es su lógica, pura para poder probarla con node.
//
// El estado de un campo es { text, cursor, anchor }: la selección va de
// anchor a cursor (en cualquier orden); sin selección, anchor === cursor.

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

function isHighSurrogate(c) { return c >= 0xD800 && c <= 0xDBFF }
function isLowSurrogate(c) { return c >= 0xDC00 && c <= 0xDFFF }

// Un paso a la izquierda / derecha sin partir un emoji (par sustituto) en dos.
function prevPos(text, pos) {
  if (pos <= 0) return 0
  if (pos >= 2 && isLowSurrogate(text.charCodeAt(pos - 1)) && isHighSurrogate(text.charCodeAt(pos - 2))) return pos - 2
  return pos - 1
}

function nextPos(text, pos) {
  if (pos >= text.length) return text.length
  if (pos + 1 < text.length && isHighSurrogate(text.charCodeAt(pos)) && isLowSurrogate(text.charCodeAt(pos + 1))) return pos + 2
  return pos + 1
}

function isWordChar(ch) {
  return /[0-9A-Za-z_À-ɏ]/.test(ch)
}

// Ctrl+←: salta los separadores y luego la palabra (como un campo normal).
function wordLeft(text, pos) {
  var i = clamp(pos, 0, text.length)
  while (i > 0 && !isWordChar(text.charAt(i - 1))) i--
  while (i > 0 && isWordChar(text.charAt(i - 1))) i--
  return i
}

function wordRight(text, pos) {
  var i = clamp(pos, 0, text.length)
  while (i < text.length && !isWordChar(text.charAt(i))) i++
  while (i < text.length && isWordChar(text.charAt(i))) i++
  return i
}

// Palabra bajo una posición (doble clic): [inicio, fin).
function wordAt(text, pos) {
  var p = clamp(pos, 0, text.length)
  var s = p, e = p
  while (s > 0 && isWordChar(text.charAt(s - 1))) s--
  while (e < text.length && isWordChar(text.charAt(e))) e++
  return [s, e]
}

// Inicio / fin de la línea lógica (entre saltos de línea).
function lineStart(text, pos) {
  return text.lastIndexOf("\n", clamp(pos, 0, text.length) - 1) + 1
}

function lineEnd(text, pos) {
  var i = text.indexOf("\n", clamp(pos, 0, text.length))
  return i < 0 ? text.length : i
}

function hasSelection(st) {
  return st.anchor !== st.cursor
}

function selectionRange(st) {
  return [Math.min(st.anchor, st.cursor), Math.max(st.anchor, st.cursor)]
}

function selectedText(st) {
  var r = selectionRange(st)
  return st.text.slice(r[0], r[1])
}

// Escribe `s` en el lugar de la selección (o en el cursor).
function replaceSelection(st, s) {
  var r = selectionRange(st)
  var str = String(s)
  var at = r[0] + str.length
  return { text: st.text.slice(0, r[0]) + str + st.text.slice(r[1]), cursor: at, anchor: at }
}

// Backspace (word = Ctrl+Backspace): borra la selección o lo de la izquierda.
function backspace(st, word) {
  if (hasSelection(st)) return replaceSelection(st, "")
  if (st.cursor <= 0) return st
  var from = word ? wordLeft(st.text, st.cursor) : prevPos(st.text, st.cursor)
  return { text: st.text.slice(0, from) + st.text.slice(st.cursor), cursor: from, anchor: from }
}

// Supr (word = Ctrl+Supr): borra la selección o lo de la derecha.
function deleteForward(st, word) {
  if (hasSelection(st)) return replaceSelection(st, "")
  if (st.cursor >= st.text.length) return st
  var to = word ? wordRight(st.text, st.cursor) : nextPos(st.text, st.cursor)
  return { text: st.text.slice(0, st.cursor) + st.text.slice(to), cursor: st.cursor, anchor: st.cursor }
}

// Ctrl+U: borra desde el inicio de la línea hasta el cursor.
function deleteToLineStart(st) {
  if (hasSelection(st)) return replaceSelection(st, "")
  var from = lineStart(st.text, st.cursor)
  if (from === st.cursor && from > 0) from = from - 1 // al inicio: se come el salto de línea
  return { text: st.text.slice(0, from) + st.text.slice(st.cursor), cursor: from, anchor: from }
}

// Filas visuales de un texto ajustado a `cols` columnas: [[inicio, fin), …].
// Corta en el último espacio que quepa; una palabra más larga que la fila se
// parte. El salto de línea no entra en ninguna fila. Un cursor justo en un
// corte suave pertenece a la fila siguiente (rowOf).
function wrap(text, cols) {
  var width = Math.max(1, Math.floor(cols))
  var rows = []
  var i = 0
  var n = text.length
  while (true) {
    var nl = text.indexOf("\n", i)
    var end = nl < 0 ? n : nl
    var s = i
    while (end - s > width) {
      var cut = s + width
      var sp = text.lastIndexOf(" ", cut - 1)
      var brk = sp >= s ? sp + 1 : cut
      if (brk <= s) brk = cut
      // no partir un par sustituto
      if (brk < end && isLowSurrogate(text.charCodeAt(brk)) && brk - 1 > s) brk--
      rows.push([s, brk])
      s = brk
    }
    rows.push([s, end])
    if (nl < 0) break
    i = nl + 1
  }
  return rows
}

// Fila visual de una posición: la última fila que empieza en o antes de pos.
function rowOf(rows, pos) {
  var lo = 0, hi = rows.length - 1
  while (lo < hi) {
    var mid = (lo + hi + 1) >> 1
    if (rows[mid][0] <= pos) lo = mid
    else hi = mid - 1
  }
  return lo
}
