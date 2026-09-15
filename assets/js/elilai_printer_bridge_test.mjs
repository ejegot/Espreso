/**
 * Node tests for assets/js/elilai_printer_bridge.js
 * Run: node assets/js/elilai_printer_bridge_test.mjs
 */
import assert from "node:assert/strict"
import {
  PRINTER_BRIDGE_UNAVAILABLE,
  isEscPosPrinterAvailable,
  resolveElilaiPrinterSend,
  sendEscPosOnce
} from "./elilai_printer_bridge.js"

let passed = 0

function test(name, fn) {
  fn()
  passed += 1
  console.log(`ok - ${name}`)
}

test("isEscPosPrinterAvailable: Plugins.EscPosPrinter present", () => {
  assert.equal(
    isEscPosPrinterAvailable({Plugins: {EscPosPrinter: {}}}),
    true
  )
})

test("isEscPosPrinterAvailable: isPluginAvailable true", () => {
  assert.equal(
    isEscPosPrinterAvailable({
      Plugins: {},
      isPluginAvailable: (name) => name === "EscPosPrinter"
    }),
    true
  )
})

test("isEscPosPrinterAvailable: nativePromise alone is false", () => {
  assert.equal(
    isEscPosPrinterAvailable({
      Plugins: {},
      nativePromise: async () => ({ok: true})
    }),
    false
  )
})

test("isEscPosPrinterAvailable: missing Capacitor is false", () => {
  assert.equal(isEscPosPrinterAvailable(undefined), false)
  assert.equal(isEscPosPrinterAvailable({}), false)
})

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
      },
      isPluginAvailable: () => true,
      nativePromise: async (...args) => {
        calls.push(["nativePromise", args])
        return {ok: true}
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
      },
      isPluginAvailable: () => true,
      nativePromise: async () => {
        calls.push("nativePromise")
        return {ok: true}
      }
    }
  }

  await sendEscPosOnce({data_base64: "Qg=="}, root)
  assert.deepEqual(calls, [{dataBase64: "Qg=="}])
})

test("nativePromise allowed when isPluginAvailable confirms EscPosPrinter", async () => {
  const calls = []
  const root = {
    Capacitor: {
      Plugins: {},
      isPluginAvailable: (name) => name === "EscPosPrinter",
      nativePromise: async (plugin, method, opts) => {
        calls.push([plugin, method, opts])
        return {ok: true}
      }
    }
  }

  await sendEscPosOnce({data_base64: "Qw=="}, root)
  assert.deepEqual(calls, [["EscPosPrinter", "send", {dataBase64: "Qw=="}]])
})

test("nativePromise exists but EscPosPrinter unavailable must not call nativePromise", async () => {
  const calls = []
  const root = {
    Capacitor: {
      Plugins: {},
      isPluginAvailable: () => false,
      nativePromise: async (...args) => {
        calls.push(args)
        return {ok: true}
      }
    }
  }

  assert.equal(resolveElilaiPrinterSend(root), null)
  await assert.rejects(
    () => sendEscPosOnce({data_base64: "Qw=="}, root),
    (err) => {
      assert.equal(err.message, PRINTER_BRIDGE_UNAVAILABLE)
      return true
    }
  )
  assert.deepEqual(calls, [])
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

test("does not double-dispatch when wrapper, plugin, and nativePromise exist", async () => {
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
      },
      isPluginAvailable: () => true,
      nativePromise: async () => {
        count += 1
        return {ok: true}
      }
    }
  }

  await sendEscPosOnce({dataBase64: "RA=="}, root)
  assert.equal(count, 1)
})

test("does not double-dispatch plugin vs nativePromise", async () => {
  let count = 0
  const root = {
    Capacitor: {
      Plugins: {
        EscPosPrinter: {
          send: async () => {
            count += 1
            return {ok: true}
          }
        }
      },
      isPluginAvailable: () => true,
      nativePromise: async () => {
        count += 1
        return {ok: true}
      }
    }
  }

  await sendEscPosOnce({dataBase64: "RQ=="}, root)
  assert.equal(count, 1)
})

console.log(`\n${passed} tests passed`)
