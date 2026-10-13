import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLib } from "./harness.mjs"

const E = loadLib("Editing.js")
const st = (text, cursor, anchor) => ({ text, cursor, anchor: anchor === undefined ? cursor : anchor })
const plain = (s) => JSON.parse(JSON.stringify(s))

test("prevPos / nextPos never split a surrogate pair", () => {
  const t = "a😀b"
  assert.equal(E.nextPos(t, 1), 3)
  assert.equal(E.prevPos(t, 3), 1)
  assert.equal(E.prevPos(t, 0), 0)
  assert.equal(E.nextPos(t, t.length), t.length)
})

test("word moves skip separators, then the word", () => {
  const t = "hola, mundo feliz"
  assert.equal(E.wordLeft(t, t.length), 12)
  assert.equal(E.wordLeft(t, 12), 6)
  assert.equal(E.wordLeft(t, 6), 0)
  assert.equal(E.wordRight(t, 0), 4)
  assert.equal(E.wordRight(t, 4), 11)
  assert.deepEqual(plain(E.wordAt(t, 8)), [6, 11])
})

test("line start / end are logical lines", () => {
  const t = "uno\ndos\ntres"
  assert.equal(E.lineStart(t, 5), 4)
  assert.equal(E.lineEnd(t, 5), 7)
  assert.equal(E.lineStart(t, 0), 0)
  assert.equal(E.lineEnd(t, 9), t.length)
})

test("replaceSelection types over the selection in any direction", () => {
  assert.deepEqual(plain(E.replaceSelection(st("abcdef", 4, 1), "X")), st("aXef", 2))
  assert.deepEqual(plain(E.replaceSelection(st("abcdef", 1, 4), "X")), st("aXef", 2))
  assert.deepEqual(plain(E.replaceSelection(st("ab", 1), "Z")), st("aZb", 2))
})

test("backspace and delete: char, word, selection and edges", () => {
  assert.deepEqual(plain(E.backspace(st("abc", 2), false)), st("ac", 1))
  assert.deepEqual(plain(E.backspace(st("a😀", 3), false)), st("a", 1))
  assert.deepEqual(plain(E.backspace(st("hola mundo", 10), true)), st("hola ", 5))
  assert.deepEqual(plain(E.backspace(st("abc", 0), false)), st("abc", 0))
  assert.deepEqual(plain(E.backspace(st("abcd", 3, 1), false)), st("ad", 1))
  assert.deepEqual(plain(E.deleteForward(st("abc", 1), false)), st("ac", 1))
  assert.deepEqual(plain(E.deleteForward(st("hola mundo", 4), true)), st("hola", 4))
  assert.deepEqual(plain(E.deleteForward(st("abc", 3), false)), st("abc", 3))
})

test("Ctrl+U deletes back to the line start, then the newline", () => {
  assert.deepEqual(plain(E.deleteToLineStart(st("uno\ndos", 6))), st("uno\ns", 4))
  assert.deepEqual(plain(E.deleteToLineStart(st("uno\ndos", 4))), st("unodos", 3))
  assert.deepEqual(plain(E.deleteToLineStart(st("abc", 3))), st("", 0))
})

test("wrap breaks at spaces, splits long words, keeps hard lines", () => {
  assert.deepEqual(plain(E.wrap("", 10)), [[0, 0]])
  assert.deepEqual(plain(E.wrap("hola mundo", 10)), [[0, 10]])
  assert.deepEqual(plain(E.wrap("hola mundo feliz", 10)), [[0, 5], [5, 11], [11, 16]])
  assert.deepEqual(plain(E.wrap("abcdefghij", 4)), [[0, 4], [4, 8], [8, 10]])
  assert.deepEqual(plain(E.wrap("ab\n\ncd", 10)), [[0, 2], [3, 3], [4, 6]])
  // ninguna fila pasa del ancho
  const t = "Lorem ipsum dolor sit amet, consectetur adipiscing elit sed do"
  for (const [s, e] of E.wrap(t, 12)) assert.ok(e - s <= 12)
})

test("rowOf: a soft break belongs to the next row, a hard line end to its own", () => {
  const rows = E.wrap("hola mundo feliz\nfin", 10)
  assert.equal(E.rowOf(rows, 0), 0)
  assert.equal(E.rowOf(rows, 5), 1) // corte suave
  assert.equal(E.rowOf(rows, 16), 2) // fin de línea lógica, antes del salto
  assert.equal(E.rowOf(rows, 17), 3)
  assert.equal(E.rowOf(rows, 20), 3)
})
