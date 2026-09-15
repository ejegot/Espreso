/**
 * Resolve a single ESC/POS send function for the ELIlai Kafe tablet bridge.
 *
 * Prefer the injected wrapper (window.ElilaiKafePrinter), then the
 * Capacitor-registered EscPosPrinter plugin stub, then Capacitor.nativePromise
 * only when EscPosPrinter is confirmed available. Never returns more than one
 * sender so callers make exactly one native send attempt per payload.
 */

export const PRINTER_BRIDGE_UNAVAILABLE =
  "Printer bridge unavailable — use the ELIlai Kafe Android app on shop Wi‑Fi"

/**
 * True when Capacitor exposes EscPosPrinter via Plugins or isPluginAvailable.
 * Bare nativePromise existence is not sufficient.
 *
 * @param {any} [cap]
 * @returns {boolean}
 */
export function isEscPosPrinterAvailable(cap) {
  if (!cap) {
    return false
  }

  if (cap.Plugins && cap.Plugins.EscPosPrinter) {
    return true
  }

  if (
    typeof cap.isPluginAvailable === "function" &&
    cap.isPluginAvailable("EscPosPrinter")
  ) {
    return true
  }

  return false
}

/**
 * @param {any} [root=globalThis]
 * @returns {null | ((opts: {dataBase64: string}) => Promise<unknown>)}
 */
export function resolveElilaiPrinterSend(root = globalThis) {
  const wrapper = root && root.ElilaiKafePrinter
  if (wrapper && typeof wrapper.send === "function") {
    return (opts) => wrapper.send(opts)
  }

  const cap = root && root.Capacitor
  const plugin = cap && cap.Plugins && cap.Plugins.EscPosPrinter

  if (plugin && typeof plugin.send === "function") {
    return (opts) => plugin.send(opts)
  }

  if (
    isEscPosPrinterAvailable(cap) &&
    cap &&
    typeof cap.nativePromise === "function"
  ) {
    return (opts) => cap.nativePromise("EscPosPrinter", "send", opts)
  }

  return null
}

/**
 * Exactly one native send attempt per call.
 *
 * @param {{data_base64?: string, dataBase64?: string}} payload
 * @param {any} [root=globalThis]
 */
export async function sendEscPosOnce(payload, root = globalThis) {
  const send = resolveElilaiPrinterSend(root)
  if (!send) {
    throw new Error(PRINTER_BRIDGE_UNAVAILABLE)
  }

  const dataBase64 = payload.data_base64 ?? payload.dataBase64
  return send({dataBase64})
}
