import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLib } from "./harness.mjs"

const A = loadLib("Actions.js")
const En = loadLib("lang/en.js").strings
const ids = arr => Array.from(arr)

test("listFor depends on the clip type", () => {
  const img = ids(A.listFor({ type: "image", path: "/a.png", ocr: "hi" }, "image"))
  assert.ok(img.includes("copyOcr") && img.includes("copyPath") && !img.includes("edit"))
  const link = ids(A.listFor({ type: "text", text: "https://x.io" }, "link"))
  assert.deepEqual(link.slice(0, 2), ["openLink", "copyDomain"])
  const one = ids(A.listFor({ type: "text", text: "one line" }, "text"))
  assert.ok(one.includes("edit") && !one.includes("sortLines"))
  const multi = ids(A.listFor({ type: "text", text: "b\na" }, "text"))
  assert.ok(multi.includes("sortLines"))
  assert.ok(ids(A.listFor({ type: "text", text: "x", pinned: true }, "text")).includes("unpin"))
})

test("every action has an icon and an English label", () => {
  const all = new Set([
    ...ids(A.listFor({ type: "image", path: "/a", ocr: "o", qr: "q" }, "image")),
    ...ids(A.listFor({ type: "files", paths: ["/a"] }, "files")),
    ...ids(A.listFor({ type: "text", text: "a\nb" }, "link")),
    ...ids(A.listFor({ type: "text", text: "#fff" }, "color")),
    ...ids(A.listFor({ type: "text", text: "{}", pinned: true }, "json"))
  ])
  for (const id of all) {
    assert.ok(A.ICONS[id], "icon " + id)
    assert.ok(En["action." + id], "label " + id)
  }
})

test("transforms", () => {
  assert.equal(A.transform("trim", "  a  \n b  \n"), "a\n b")
  assert.equal(A.transform("upper", "Hola"), "HOLA")
  assert.equal(A.transform("title", "hola mundo-azul"), "Hola Mundo-Azul")
  assert.equal(A.transform("sortLines", "b\nA\nc"), "A\nb\nc")
  assert.equal(A.transform("dedupeLines", "a\nb\na"), "a\nb")
  assert.equal(A.transform("removeEmptyLines", "a\n\n \nb"), "a\nb")
  assert.equal(A.transform("joinLines", " a \n\n b "), "a b")
  assert.equal(A.transform("jsonMinify", '{ "a": [1, 2] }'), '{"a":[1,2]}')
  assert.equal(A.transform("jsonPretty", '{"a":1}'), '{\n  "a": 1\n}')
  assert.equal(A.transform("jsonPretty", "nope"), null)
})

test("matches filters by every word", () => {
  assert.ok(A.matches("Copy as HEX", "copy hex"))
  assert.ok(!A.matches("Copy as HEX", "copy rgb"))
  assert.ok(A.matches("Anything", ""))
})
