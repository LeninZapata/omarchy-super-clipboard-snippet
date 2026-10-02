import { test } from "node:test"
import assert from "node:assert/strict"
import { loadLib } from "./harness.mjs"

const S = loadLib("Snippets.js")
const En = loadLib("lang/en.js").strings
const Es = loadLib("lang/es.js").strings
const names = arr => Array.from(arr, s => s.name)

test("normalize, slug cleanup and round-trip", () => {
  const list = S.parseList(JSON.stringify([
    { id: "a", name: " Banco ", slug: " __Target Banco ", body: "x" },
    { name: "", body: "  " },
    { id: "a", name: "dup id", body: "y" }
  ]), 100)
  assert.equal(list.length, 1)
  assert.equal(list[0].name, "Banco")
  assert.equal(list[0].slug, "__target_banco")
  assert.equal(S.parseList(S.serialize(list), 1)[0].slug, "__target_banco")
  assert.equal(S.parseList("garbage").length, 0)
})

test("upsert, remove, slugTaken and merge", () => {
  let r = S.upsert([], { name: "One", slug: "one", body: "1" }, 10)
  let list = r.list
  r = S.upsert(list, { id: r.id, name: "One!", slug: "one", body: "1b" }, 20)
  assert.equal(r.list.length, 1)
  assert.equal(r.list[0].name, "One!")
  assert.equal(r.list[0].createdAt, 10)
  assert.equal(r.list[0].updatedAt, 20)
  list = S.upsert(r.list, { name: "Two", slug: "two", body: "2" }, 30).list
  assert.ok(S.slugTaken(list, "ONE", "other"))
  assert.ok(!S.slugTaken(list, "one", r.id))
  const m = S.merge(list, [{ name: "One new", slug: "one", body: "n" }, { name: "Three", slug: "three", body: "3" }], 40)
  assert.equal(m.added, 1)
  assert.equal(m.updated, 1)
  assert.equal(m.list.length, 3)
  assert.equal(S.remove(m.list, r.id).length, 2)
})

test("search by slug and name, slug ranks first", () => {
  const list = S.parseList(JSON.stringify([
    { id: "1", name: "Cuenta Banco Guayaquil", slug: "__target_banco_guayaquil", body: "" },
    { id: "2", name: "Banco Pichincha", slug: "__bp", body: "" },
    { id: "3", name: "Firma", slug: "firma", body: "banco en el texto no cuenta" }
  ]), 1)
  assert.deepEqual(names(S.search(list, "__banco_g")), ["Cuenta Banco Guayaquil"])
  assert.deepEqual(names(S.search(list, "banco")), ["Cuenta Banco Guayaquil", "Banco Pichincha"])
  assert.deepEqual(names(S.search(list, "firma")), ["Firma"])
  assert.deepEqual(names(S.search(list, "")), ["Banco Pichincha", "Cuenta Banco Guayaquil", "Firma"])
})

test("render variables in English and Spanish", () => {
  const now = new Date(2026, 9, 1, 19, 5, 9)
  const body = "{date_short}|{date_medium}|{date_long}|{date_iso}|{time}|{time_12}|{time_seconds}|{weekday}|{month}|{day}|{year}|{clipboard}|{nope}"
  assert.equal(S.render(body, { now, L: En, clipboard: "clip" }),
    "10/01/2026|Oct 1, 2026|Thursday, October 1, 2026|2026-10-01|19:05|7:05 PM|19:05:09|Thursday|October|1|2026|clip|{nope}")
  assert.equal(S.render(body, { now, L: Es, clipboard: "clip" }),
    "01/10/2026|1 oct 2026|jueves, 1 de octubre de 2026|2026-10-01|19:05|7:05 PM|19:05:09|jueves|octubre|1|2026|clip|{nope}")
})

test("every variable has a description in both languages", () => {
  for (const v of S.VARIABLES) {
    assert.ok(En["var." + v], "en " + v)
    assert.ok(Es["var." + v], "es " + v)
  }
})
