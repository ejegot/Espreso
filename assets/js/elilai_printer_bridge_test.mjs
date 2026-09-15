/**
 * Node tests for assets/js/elilai_printer_bridge.js
 * Run: node assets/js/elilai_printer_bridge_test.mjs
 */
import assert from "node:assert/strict"
import {
  PRINTER_BRIDGE_UNAVAILABLE,
  resolveElilaiPrinterSend,
  sendEscPosOnce
} from "./elilai_printer_bridge.js"

let passed = 0

function test(name, fn) {
  fn()
  passed += 1
  console.log(`ok - ${name}`)
}

test("prefers ElilaiKafePrinter wrapper when present", async () => {
  const calls = []
  const root = {
    ElilaiKafePrinter: {
      send: async (opts) => {
        calls.push(["wrapper", opts])
        return {ok: true}
      }
    },
    Capacitor: {
      Plugins: {
        EscPosPrinter: {
          send: async (opts) => {
            calls.push(["plugin", opts])
            return {ok: true}
          }
        }
      }
    }
  }

  const send = resolveElilaiPrinterSend(root)
  assert.equal(typeof send, "function")
  await sendEscPosOnce({data_base64: "QQ=="}, root)
  assert.deepEqual(calls, [["wrapper", {dataBase64: "QQ=="}]])
})

test("falls back to Capacitor.Plugins.EscPosPrinter once", async () => {
  const calls = []
  const root = {
    Capacitor: {
      Plugins: {
        EscPosPrinter: {
          send: async (opts) => {
            calls.push(opts)
            return {ok: true}
          }
        }
      }
    }
  }

  await sendEscPosOnce({data_base64: "Qg=="}, root)
  assert.deepEqual(calls, [{dataBase64: "Qg=="}])
})

test("unavailable bridge throws the existing clear error", async () => {
  await assert.rejects(
    () => sendEscPosOnce({data_base64: "Qw=="}, {}),
    (err) => {
      assert.equal(err.message, PRINTER_BRIDGE_UNAVAILABLE)
      return true
    }
  )
  assert.equal(resolveElilaiPrinterSend({}), null)
})

test("does not double-dispatch when both wrapper and plugin exist", async () => {
  let count = 0
  const root = {
    ElilaiKafePrinter: {
      send: async () => {
        count += 1
        return {ok: true}
      }
    },
    Capacitor: {
      Plugins: {
        EscPosPrinter: {
          send: async () => {
            count += 1
            return {ok: true}
          }
        }
      }
    }
  }

  await sendEscPosOnce({dataBase64: "RA=="}, root)
  assert.equal(count, 1)
})

console.log(`\n${passed} tests passed`)
