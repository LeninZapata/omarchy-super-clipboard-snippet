import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLib } from "./harness.mjs"

const En = loadLib("lang/en.js").strings
const Es = loadLib("lang/es.js").strings
const Classify = loadLib("Classify.js")

test("lang files have exactly the same keys", () => {
  const en = Object.keys(En).sort()
  const es = Object.keys(Es).sort()
  assert.deepEqual(es.filter(k => !en.includes(k)), [], "keys only in es")
  assert.deepEqual(en.filter(k => !es.includes(k)), [], "keys missing in es")
})

test("placeholders match between languages", () => {
  const ph = s => (String(s).match(/\{\w+\}/g) || []).sort().join(",")
  for (const k of Object.keys(En)) assert.equal(ph(Es[k]), ph(En[k]), k)
})

test("Classify texts follow the language dictionary", () => {
  assert.equal(Classify.typeLabel("image", Es), "Imagen")
  assert.equal(Classify.typeLabel("image"), "Image")
  assert.equal(Classify.plural(3, "word", Es), "3 palabras")
  assert.equal(Classify.plural(1, "line", Es), "1 línea")
  assert.equal(Classify.formatAge(1000, 1000 + 600, Es), "hace 10 min")
  assert.equal(Classify.formatAge(1000, 1000 + 600), "10m ago")
  const ts = new Date(2026, 9, 1, 18, 5, 9).getTime() / 1000
  assert.equal(Classify.formatFullDate(ts, Es), "1 oct 2026, 18:05:09")
  assert.equal(Classify.formatFullDate(ts), "Oct 1, 2026 at 18:05:09")
})
