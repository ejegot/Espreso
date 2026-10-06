// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {sendEscPosOnce} from "./elilai_printer_bridge"

const Hooks = {}

Hooks.SmoothScroll = {
  mounted() {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const coarse = window.matchMedia("(pointer: coarse)").matches

    this.reduce = reduce

    if (reduce) return

    document.documentElement.style.scrollBehavior = "smooth"

    this.current = window.scrollY
    this.target = window.scrollY
    this.running = false
    this.lastTime = performance.now()
    this.ease = coarse ? 0.08 : 0.024
    this.wheelScale = coarse ? 1 : 0.85
    this.stopAt = 0.08

    if (coarse) return

    this.isLocked = () =>
      document.querySelector(".menu-page-locked, .menu-buy-layer, #menu-basket")

    this.inScrollable = (target) => {
      let node = target
      while (node && node !== document.body) {
        const style = window.getComputedStyle(node)
        const scrollableX =
          (style.overflowX === "auto" || style.overflowX === "scroll") &&
          node.scrollWidth > node.clientWidth + 1
        const scrollableY =
          (style.overflowY === "auto" || style.overflowY === "scroll") &&
          node.scrollHeight > node.clientHeight + 1

        if (scrollableX || scrollableY) return true
        node = node.parentElement
      }

      return false
    }

    this.onWheel = (event) => {
      if (document.querySelector(".menu-live-root")) return
      if (this.isLocked() || this.inScrollable(event.target)) return
      if (event.ctrlKey) return
      event.preventDefault()
      const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
      this.target = Math.max(
        0,
        Math.min(max, this.target + event.deltaY * this.wheelScale)
      )
      if (!this.running) {
        this.lastTime = performance.now()
        this.raf = requestAnimationFrame(this.loop)
      }
    }

    this.loop = (time) => {
      const dt = Math.min(48, time - this.lastTime)
      this.lastTime = time
      const factor = 1 - Math.pow(1 - this.ease, dt / 16.67)

      this.running = true
      this.current += (this.target - this.current) * factor

      if (Math.abs(this.target - this.current) < this.stopAt) {
        this.current = this.target
        window.scrollTo(0, this.current)
        this.running = false
        this.raf = null
        return
      }

      window.scrollTo(0, this.current)
      this.raf = requestAnimationFrame(this.loop)
    }

    this.sync = () => {
      if (this.running) return
      this.current = window.scrollY
      this.target = window.scrollY
    }

    this.scrollToTop = () => {
      this.target = 0
      this.current = window.scrollY
      if (this.current < 1) {
        this.current = 0
        window.scrollTo(0, 0)
        return
      }
      if (!this.running) {
        this.lastTime = performance.now()
        this.raf = requestAnimationFrame(this.loop)
      }
    }

    this.onNavigate = () => {
      if (this.lastPath === window.location.pathname) return
      this.lastPath = window.location.pathname
      this.scrollToTop()
    }

    this.lastPath = window.location.pathname

    this.onProgrammaticScroll = (event) => {
      event.preventDefault()
      const top = event.detail?.top ?? 0
      this.current = window.scrollY
      this.target = top
      if (event.detail?.reduce) {
        this.current = top
        this.running = false
        if (this.raf) cancelAnimationFrame(this.raf)
        window.scrollTo(0, top)
        return
      }
      if (!this.running) {
        this.lastTime = performance.now()
        this.raf = requestAnimationFrame(this.loop)
      }
    }

    window.addEventListener("wheel", this.onWheel, {passive: false})
    window.addEventListener("scroll", this.sync, {passive: true})
    window.addEventListener("phx:page-loading-stop", this.onNavigate)
    window.addEventListener("site:scroll-to", this.onProgrammaticScroll)
  },

  destroyed() {
    document.documentElement.style.scrollBehavior = ""
    if (this.onWheel) window.removeEventListener("wheel", this.onWheel)
    if (this.sync) window.removeEventListener("scroll", this.sync)
    if (this.onNavigate) window.removeEventListener("phx:page-loading-stop", this.onNavigate)
    if (this.onProgrammaticScroll) window.removeEventListener("site:scroll-to", this.onProgrammaticScroll)
    if (this.raf) cancelAnimationFrame(this.raf)
  }
}

const MENU_CART_STORAGE_KEY = "coffeespot.menu.cart.v1"
const MY_ORDERS_STORAGE_KEY = "coffeespot.orders.v1"
const LOYALTY_PHONE_STORAGE_KEY = "coffeespot.loyalty_phone.v1"
const LEGACY_CURRENT_ORDER_STORAGE_KEY = "coffeespot.current_order.v1"
const MY_ORDERS_MAX = 20
const ORDER_NUMBER_PATTERN = /^CS-[2-9A-HJ-NP-Z]{6}$/

function isValidOrderNumber(value) {
  return typeof value === "string" && ORDER_NUMBER_PATTERN.test(value.trim())
}

function readMyOrderNumbers() {
  try {
    const raw = localStorage.getItem(MY_ORDERS_STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      const numbers = Array.isArray(parsed?.numbers) ? parsed.numbers : []
      return sanitizeOrderNumbers(numbers)
    }

    // One-time migrate legacy single-order pointer.
    const legacyRaw = localStorage.getItem(LEGACY_CURRENT_ORDER_STORAGE_KEY)
    if (!legacyRaw) return []

    const legacy = JSON.parse(legacyRaw)
    const legacyNumber =
      typeof legacy?.number === "string" ? legacy.number.trim() : ""
    const migrated = sanitizeOrderNumbers([legacyNumber])
    writeMyOrderNumbers(migrated)
    try {
      localStorage.removeItem(LEGACY_CURRENT_ORDER_STORAGE_KEY)
    } catch (_error) {
      // no-op
    }
    return migrated
  } catch (_error) {
    return []
  }
}

function sanitizeOrderNumbers(numbers) {
  if (!Array.isArray(numbers)) return []
  const seen = new Set()
  const cleaned = []
  for (const value of numbers) {
    if (!isValidOrderNumber(value)) continue
    const number = String(value).trim()
    if (seen.has(number)) continue
    seen.add(number)
    cleaned.push(number)
    if (cleaned.length >= MY_ORDERS_MAX) break
  }
  return cleaned
}

function writeMyOrderNumbers(numbers) {
  try {
    const cleaned = sanitizeOrderNumbers(numbers)
    if (!cleaned.length) {
      localStorage.removeItem(MY_ORDERS_STORAGE_KEY)
      return []
    }
    localStorage.setItem(MY_ORDERS_STORAGE_KEY, JSON.stringify({numbers: cleaned}))
    return cleaned
  } catch (_error) {
    return sanitizeOrderNumbers(numbers)
  }
}

function appendMyOrderNumber(number) {
  if (!isValidOrderNumber(number)) return readMyOrderNumbers()
  const value = String(number).trim()
  const existing = readMyOrderNumbers().filter((n) => n !== value)
  return writeMyOrderNumbers([...existing, value])
}

function readLoyaltyPhone() {
  try {
    const raw = localStorage.getItem(LOYALTY_PHONE_STORAGE_KEY)
    if (!raw) return ""
    const parsed = JSON.parse(raw)
    const phone = typeof parsed?.phone === "string" ? parsed.phone.trim() : ""
    return phone
  } catch (_error) {
    return ""
  }
}

function writeLoyaltyPhone(phone) {
  try {
    const value = typeof phone === "string" ? phone.trim() : ""
    if (!value) {
      localStorage.removeItem(LOYALTY_PHONE_STORAGE_KEY)
      return ""
    }
    localStorage.setItem(LOYALTY_PHONE_STORAGE_KEY, JSON.stringify({phone: value}))
    return value
  } catch (_error) {
    return ""
  }
}

function clearLoyaltyPhone() {
  try {
    localStorage.removeItem(LOYALTY_PHONE_STORAGE_KEY)
  } catch (_error) {
    // no-op
  }
}

Hooks.OrderConfirm = {
  mounted() {
    try {
      localStorage.removeItem(MENU_CART_STORAGE_KEY)
    } catch (_error) {
      // Ignore private-mode / storage failures.
    }

    this.appendOrderNumber()
  },

  appendOrderNumber() {
    const number = (this.el.dataset.orderNumber || "").trim()
    appendMyOrderNumber(number)
  }
}

Hooks.StaffOrdersBoard = {
  mounted() {
    // Chime moved to StaffNotifications (shell bell + mute).
  }
}

Hooks.StaffNotifications = {
  mounted() {
    this.muteKey = "coffeespot.staff.soundMuted"
    this.el.addEventListener("click", (event) => {
      const btn = event.target.closest("[data-staff-notif-mute]")
      if (!btn || !this.el.contains(btn)) return

      const next = !this.isMuted()
      try {
        localStorage.setItem(this.muteKey, next ? "1" : "0")
      } catch (_error) {
        // Ignore private-mode / storage failures.
      }
      this.syncMuteLabel()
    })

    this.handleEvent("staff_notify_chime", () => this.playChime())
    this.syncMuteLabel()
  },

  updated() {
    this.syncMuteLabel()
  },

  isMuted() {
    try {
      return localStorage.getItem(this.muteKey) === "1"
    } catch (_error) {
      return false
    }
  },

  syncMuteLabel() {
    const muteBtn = this.el.querySelector("[data-staff-notif-mute]")
    if (!muteBtn) return
    const muted = this.isMuted()
    muteBtn.textContent = muted ? "Sound off" : "Sound on"
    muteBtn.setAttribute("aria-pressed", muted ? "true" : "false")
    muteBtn.classList.toggle("is-muted", muted)
  },

  playChime() {
    if (this.isMuted()) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext
      if (!AudioContext) return

      const ctx = new AudioContext()
      const oscillator = ctx.createOscillator()
      const gain = ctx.createGain()

      oscillator.type = "sine"
      oscillator.frequency.setValueAtTime(880, ctx.currentTime)
      gain.gain.setValueAtTime(0.0001, ctx.currentTime)
      gain.gain.exponentialRampToValueAtTime(0.08, ctx.currentTime + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.35)

      oscillator.connect(gain)
      gain.connect(ctx.destination)
      oscillator.start()
      oscillator.stop(ctx.currentTime + 0.36)
      oscillator.onended = () => ctx.close()
    } catch (_error) {
      // Ignore autoplay / audio failures.
    }
  }
}

// Keeps hamburger aria-expanded in sync with the LiveComponent drawer open state.
Hooks.StaffNavDrawer = {
  mounted() {
    this.syncOpenButtons()
  },

  updated() {
    this.syncOpenButtons()
  },

  syncOpenButtons() {
    const open = this.el.getAttribute("data-open") === "true"
    document.querySelectorAll("[data-staff-nav-menu-open]").forEach((btn) => {
      btn.setAttribute("aria-expanded", open ? "true" : "false")
      btn.setAttribute("aria-label", open ? "Close navigation menu" : "Open navigation menu")
      btn.classList.toggle("is-active", open)
    })

    if (open) {
      const closeBtn = this.el.querySelector("#staff-nav-menu-close")
      if (closeBtn && typeof closeBtn.focus === "function") {
        window.requestAnimationFrame(() => closeBtn.focus())
      }
    }
  }
}

// Native Capacitor ESC/POS bridge (tablet → LAN printer). Phoenix only builds bytes.
Hooks.ElilaiPrinter = {
  mounted() {
    this.handleEvent("elilai-printer", (payload) => this.sendPayload(payload))
  },

  async sendPayload(payload) {
    const reply = {
      order_id: String(payload.order_id ?? ""),
      action: payload.action,
      permit: payload.permit,
      request_id: payload.request_id,
      flow: payload.flow
    }

    try {
      // Prefer injected window.ElilaiKafePrinter; fall back to Cap.Plugins.EscPosPrinter.
      // sendEscPosOnce guarantees a single native send attempt (no duplicate kicks/prints).
      await sendEscPosOnce(payload)
      this.pushEvent("elilai_printer_result", Object.assign({ok: true}, reply))
    } catch (error) {
      const message = error && error.message ? error.message : String(error)
      this.pushEvent(
        "elilai_printer_result",
        Object.assign({ok: false, error: message}, reply)
      )
    }
  }
}

// Client-side PIN pad for staff login. Collects digits locally only —
// verification remains server-side via POST /session/pin.
Hooks.StaffPinPad = {
  mounted() {
    this.pin = ""
    this.input = this.el.querySelector("[data-pin-input]")
    this.dots = Array.from(this.el.querySelectorAll("[data-pin-dot]"))
    this.keys = Array.from(this.el.querySelectorAll("[data-pin-key], [data-pin-action]"))
    this.form = this.el.closest("form")
    this.submit =
      this.el.querySelector("[data-pin-submit]") ||
      (this.form && this.form.querySelector("[data-pin-submit]"))
    this.staffId = this.el.dataset.staffId || ""

    this.onClick = (event) => {
      const target = event.target.closest("[data-pin-key], [data-pin-action]")
      if (!target || !this.el.contains(target) || target.disabled) return

      event.preventDefault()
      if (!this.isReady()) return

      const digit = target.getAttribute("data-pin-key")
      const action = target.getAttribute("data-pin-action")

      if (digit) this.appendDigit(digit)
      else if (action === "backspace") this.backspace()
      else if (action === "clear") this.clearPin()
    }

    this.onSubmit = () => {
      if (this.submit) {
        this.submit.disabled = true
        this.submit.setAttribute("aria-busy", "true")
        this.submit.classList.add("is-loading")
      }
    }

    this.el.addEventListener("click", this.onClick)
    if (this.form) this.form.addEventListener("submit", this.onSubmit)

    this.syncReady()
    this.render()
  },

  updated() {
    const nextStaffId = this.el.dataset.staffId || ""
    if (nextStaffId !== this.staffId) {
      this.staffId = nextStaffId
      this.clearPin()
    }
    this.submit =
      this.el.querySelector("[data-pin-submit]") ||
      (this.form && this.form.querySelector("[data-pin-submit]"))
    this.syncReady()
    this.render()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    if (this.form && this.onSubmit) this.form.removeEventListener("submit", this.onSubmit)
  },

  isReady() {
    return this.el.dataset.pinReady === "true"
  },

  pinMax() {
    return Number(this.el.dataset.pinMax || 6)
  },

  pinDisplay() {
    return Number(this.el.dataset.pinDisplay || 4)
  },

  appendDigit(digit) {
    if (!/^\d$/.test(digit)) return
    if (this.pin.length >= this.pinMax()) return
    this.pin += digit
    this.render()
  },

  backspace() {
    this.pin = this.pin.slice(0, -1)
    this.render()
  },

  clearPin() {
    this.pin = ""
    this.render()
  },

  syncReady() {
    const ready = this.isReady()
    this.keys.forEach((key) => {
      key.disabled = !ready
    })
    if (this.submit && this.submit.getAttribute("aria-busy") !== "true") {
      this.submit.disabled = !(ready && this.pin.length >= 4)
    }
  },

  render() {
    if (this.input) this.input.value = this.pin

    const filledCount =
      this.pin.length >= this.pinDisplay() ? this.pinDisplay() : this.pin.length

    this.dots.forEach((dot) => {
      const index = Number(dot.dataset.index || 0)
      dot.classList.toggle("is-filled", index > 0 && index <= filledCount)
    })

    this.syncReady()
  }
}

Hooks.MenuBrowse = {
  mounted() {
    this.handleEvent("scroll_to_items", () => this.scrollToItems())
    this.handleEvent("scroll_to_category", ({name}) => this.scrollToCategory(name))
    this.handleEvent("scroll_to_menu_content", () => this.scrollToMenuContent())
    this.handleEvent("scroll_active_chip", ({id, behavior}) =>
      this.scrollActiveChip(id, behavior)
    )
    this.handleEvent("scroll_basket_top", () => this.scrollBasketTop())
    this.handleEvent("focus_menu_search", () => this.focusMenuSearch())
    this.handleEvent("clear_persisted_cart", () => this.clearPersistedCart())
    this.handleEvent("persist_my_order", ({number}) => this.persistMyOrder(number))
    this.handleEvent("persist_current_order", ({number}) => this.persistMyOrder(number))
    this.handleEvent("sync_my_orders", ({numbers}) => this.syncMyOrders(numbers))
    this.handleEvent("clear_my_orders", () => this.clearMyOrders())
    this.handleEvent("clear_current_order", () => this.clearMyOrders())
    this.handleEvent("persist_loyalty_phone", ({phone}) => this.persistLoyaltyPhone(phone))
    this.handleEvent("clear_loyalty_phone", () => this.clearLoyaltyPhoneStorage())

    this.onChipClick = (event) => {
      const chip = event.target.closest(".menu-craving-chip")
      if (chip instanceof HTMLElement) chip.blur()
    }

    this.el.addEventListener("click", this.onChipClick)
    this.onAddPointer = (event) => {
      const origin = event.target.closest(
        ".brune-menu-add, .menu-buy-now, .menu-signature-card, .brune-menu-item-open"
      )
      if (!(origin instanceof HTMLElement)) return

      const root =
        origin.closest("article, .menu-signature-card, #menu-buy-panel, #menu-page") ||
        origin
      const img = root.querySelector("img")
      this._flyFrom = {
        rect: origin.getBoundingClientRect(),
        src: img instanceof HTMLImageElement ? img.currentSrc || img.src : "",
      }
    }
    this.el.addEventListener("pointerdown", this.onAddPointer, true)
    this._lastBagFly = this.el.dataset.bagFly || "0"
    this.bindCategorySwipe()
    this.restorePersistedCart()
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        this.ensureMyOrdersRestored()
        this.ensureLoyaltyPhoneRestored()
      })
    )
    this.persistCartFromDom()
    this.syncShellChrome()
  },

  updated() {
    this.persistCartFromDom()
    this.ensureMyOrdersRestored()
    this.ensureLoyaltyPhoneRestored()
    this.maybeFlyToBag()
    this.bindCategorySwipe()
    this.playSwipeIn()
    this.syncShellChrome()
  },

  destroyed() {
    if (this.onChipClick) this.el.removeEventListener("click", this.onChipClick)
    if (this.onAddPointer) this.el.removeEventListener("pointerdown", this.onAddPointer, true)
    this.unbindCategorySwipe()
    this.clearShellChrome()
  },

  syncShellChrome() {
    const landing = Boolean(this.el.querySelector("#menu-landing"))
    const dark = Boolean(
      landing ||
        this.el.classList.contains("menu-live-root--glass") ||
        this.el.classList.contains("menu-live-root--qr-entry")
    )
    const color = landing ? "#1a100c" : dark ? "#382010" : "#FAF7F4"
    const theme = document.querySelector('meta[name="theme-color"]')
    if (theme) theme.setAttribute("content", color)
    const bar = document.querySelector('meta[name="apple-mobile-web-app-status-bar-style"]')
    if (bar) bar.setAttribute("content", dark ? "black-translucent" : "default")
  },

  clearShellChrome() {
    const theme = document.querySelector('meta[name="theme-color"]')
    if (theme) theme.setAttribute("content", "#FAF7F4")
    const bar = document.querySelector('meta[name="apple-mobile-web-app-status-bar-style"]')
    if (bar) bar.setAttribute("content", "default")
  },

  bindCategorySwipe() {
    const items = this.el.querySelector("#menu-items")
    if (items === this._swipeEl) return
    this.unbindCategorySwipe()
    this._swipeEl = items instanceof HTMLElement ? items : null
    if (!this._swipeEl) return

    this._onSwipePointerDown = (event) => this.beginCategorySwipe(event)
    this._onSwipePointerMove = (event) => this.moveCategorySwipe(event)
    this._onSwipePointerUp = (event) => this.endCategorySwipe(event)
    this._onSwipeClick = (event) => this.suppressSwipeClick(event)

    this._swipeEl.addEventListener("pointerdown", this._onSwipePointerDown, true)
    this._swipeEl.addEventListener("pointermove", this._onSwipePointerMove, true)
    this._swipeEl.addEventListener("pointerup", this._onSwipePointerUp, true)
    this._swipeEl.addEventListener("pointercancel", this._onSwipePointerUp, true)
    this._swipeEl.addEventListener("click", this._onSwipeClick, true)
  },

  unbindCategorySwipe() {
    if (!this._swipeEl) return
    this._swipeEl.removeEventListener("pointerdown", this._onSwipePointerDown, true)
    this._swipeEl.removeEventListener("pointermove", this._onSwipePointerMove, true)
    this._swipeEl.removeEventListener("pointerup", this._onSwipePointerUp, true)
    this._swipeEl.removeEventListener("pointercancel", this._onSwipePointerUp, true)
    this._swipeEl.removeEventListener("click", this._onSwipeClick, true)
    this._swipeEl = null
  },

  categorySwipeEnabled() {
    return this.el.dataset.categorySwipe === "1"
  },

  beginCategorySwipe(event) {
    if (!this.categorySwipeEnabled()) return
    if (event.pointerType === "mouse" && event.button !== 0) return
    if (event.target.closest("a, input, textarea, select, .menu-item-heart")) return

    this._swipe = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      axis: null,
      locked: false,
      previewDir: null,
    }
  },

  moveCategorySwipe(event) {
    const swipe = this._swipe
    if (!swipe || swipe.id !== event.pointerId) return

    const dx = event.clientX - swipe.x
    const dy = event.clientY - swipe.y
    if (!swipe.axis) {
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10) return
      swipe.axis = Math.abs(dx) > Math.abs(dy) * 1.15 ? "x" : "y"
      if (swipe.axis === "x" && this._swipeEl) {
        swipe.locked = true
        try {
          this._swipeEl.setPointerCapture(event.pointerId)
        } catch (_error) {
          /* ignore */
        }
      }
    }

    if (swipe.axis !== "x") return
    event.preventDefault()
    this.dragCategorySwipe(dx)
  },

  dragCategorySwipe(dx) {
    const items = this._swipeEl
    if (!(items instanceof HTMLElement)) return

    const dir = dx < 0 ? "next" : "prev"
    const hasNeighbor = this.hasSwipeNeighbor(dir)
    const width = Math.max(items.clientWidth, 1)
    const rubber = hasNeighbor ? 1 : 0.22
    const travel = Math.max(-width * 0.38, Math.min(width * 0.38, dx * rubber))
    items.style.transition = "none"
    items.style.transform = `translate3d(${travel}px, 0, 0)`
    items.style.opacity = String(1 - Math.min(0.22, Math.abs(travel) / width))

    if (hasNeighbor && Math.abs(dx) > 36) {
      this.previewSwipeChip(dir)
    } else {
      this.clearSwipePreview()
    }
  },

  endCategorySwipe(event) {
    const swipe = this._swipe
    this._swipe = null
    if (!swipe || swipe.id !== event.pointerId || swipe.axis !== "x") return

    const dx = event.clientX - swipe.x
    if (Math.abs(dx) < 48) {
      this.clearSwipePreview()
      this.settleCategorySwipe(0, 1)
      return
    }

    this.commitCategorySwipe(dx < 0 ? "next" : "prev")
  },

  hasSwipeNeighbor(dir) {
    return Boolean(this.neighborSwipeChip(dir))
  },

  neighborSwipeChip(dir) {
    const chips = Array.from(this.el.querySelectorAll("#menu-craving .menu-craving-chip"))
    const index = chips.findIndex((chip) => chip.classList.contains("is-active"))
    if (index < 0) return null
    return (dir === "next" ? chips[index + 1] : chips[index - 1]) || null
  },

  previewSwipeChip(dir) {
    const next = this.neighborSwipeChip(dir)
    if (!next || this._previewChip === next) return
    this.clearSwipePreview()
    next.classList.add("is-swipe-preview")
    this._previewChip = next
    this.scrollActiveChip(next.id, "smooth")
  },

  followSwipeChip(dir) {
    const next = this.neighborSwipeChip(dir)
    if (!(next instanceof HTMLElement)) return
    this.clearSwipePreview()
    this.el.querySelectorAll("#menu-craving .menu-craving-chip.is-active").forEach((chip) => {
      chip.classList.remove("is-active")
      chip.setAttribute("aria-pressed", "false")
      chip.removeAttribute("aria-current")
    })
    next.classList.add("is-active")
    next.setAttribute("aria-pressed", "true")
    next.setAttribute("aria-current", "true")
    this.scrollActiveChip(next.id, "smooth")
  },

  clearSwipePreview() {
    if (this._previewChip instanceof HTMLElement) {
      this._previewChip.classList.remove("is-swipe-preview")
    }
    this._previewChip = null
  },

  settleCategorySwipe(x, opacity) {
    const items = this._swipeEl
    if (!(items instanceof HTMLElement)) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.resetSwipeTransform(items)
      return
    }
    items.style.transition =
      "transform 0.32s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.32s ease"
    items.style.transform = `translate3d(${x}px, 0, 0)`
    items.style.opacity = String(opacity)
    if (x === 0) {
      window.setTimeout(() => this.resetSwipeTransform(items), 340)
    }
  },

  resetSwipeTransform(items) {
    if (!(items instanceof HTMLElement)) return
    items.style.transition = ""
    items.style.transform = ""
    items.style.opacity = ""
  },

  bounceCategorySwipe(dx) {
    this.settleCategorySwipe(dx < 0 ? -18 : 18, 1)
    window.setTimeout(() => this.settleCategorySwipe(0, 1), 160)
  },

  commitCategorySwipe(dir) {
    if (!this.hasSwipeNeighbor(dir)) {
      this.clearSwipePreview()
      this.bounceCategorySwipe(dir === "next" ? -80 : 80)
      return
    }

    const items = this._swipeEl
    this._pendingSwipeIn = dir
    this._didSwipe = true
    window.setTimeout(() => {
      this._didSwipe = false
    }, 450)

    this.followSwipeChip(dir)

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reduce || !(items instanceof HTMLElement)) {
      this.resetSwipeTransform(items)
      this.pushEvent("swipe_category", {dir})
      return
    }

    const width = Math.max(items.clientWidth, 1)
    this.settleCategorySwipe(dir === "next" ? -width * 0.18 : width * 0.18, 0.72)
    this.pushEvent("swipe_category", {dir})
  },

  playSwipeIn() {
    const dir = this._pendingSwipeIn
    this._pendingSwipeIn = null
    const items = this.el.querySelector("#menu-items")
    if (!dir || !(items instanceof HTMLElement)) return
    this.clearSwipePreview()
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.resetSwipeTransform(items)
      return
    }

    const from = dir === "next" ? "14%" : "-14%"
    items.style.transition = "none"
    items.style.transform = `translate3d(${from}, 0, 0)`
    items.style.opacity = "0.62"
    void items.offsetWidth
    items.style.transition =
      "transform 0.36s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.36s ease"
    items.style.transform = "translate3d(0, 0, 0)"
    items.style.opacity = "1"
    window.setTimeout(() => this.resetSwipeTransform(items), 380)
  },

  suppressSwipeClick(event) {
    if (!this._didSwipe) return
    event.preventDefault()
    event.stopPropagation()
  },

  maybeFlyToBag() {
    const token = this.el.dataset.bagFly || "0"
    if (!token || token === "0" || token === this._lastBagFly) return
    this._lastBagFly = token
    this.flyAddedItemToBag()
  },

  flyAddedItemToBag() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const bag = this.el.querySelector("#menu-qr-bag")
    if (!(bag instanceof HTMLElement)) return

    const from = this._flyFrom && this._flyFrom.rect
    const start = from || { left: window.innerWidth / 2, top: window.innerHeight * 0.55, width: 40, height: 40 }
    const end = bag.getBoundingClientRect()
    const orb = document.createElement(this._flyFrom && this._flyFrom.src ? "img" : "span")
    orb.className = "menu-bag-fly"
    if (orb instanceof HTMLImageElement) {
      orb.src = this._flyFrom.src
      orb.alt = ""
    }
    const size = 38
    orb.style.left = `${start.left + start.width / 2 - size / 2}px`
    orb.style.top = `${start.top + start.height / 2 - size / 2}px`
    document.body.appendChild(orb)

    const dx = end.left + end.width / 2 - size / 2 - (start.left + start.width / 2 - size / 2)
    const dy = end.top + end.height / 2 - size / 2 - (start.top + start.height / 2 - size / 2)
    const anim = orb.animate(
      [
        { transform: "translate(0, 0) scale(1)", opacity: 1 },
        { transform: `translate(${dx * 0.55}px, ${dy * 0.35 - 48}px) scale(0.72)`, opacity: 1, offset: 0.55 },
        { transform: `translate(${dx}px, ${dy}px) scale(0.28)`, opacity: 0.35 },
      ],
      { duration: 560, easing: "cubic-bezier(0.22, 1, 0.36, 1)", fill: "forwards" }
    )
    const cleanup = () => orb.remove()
    if (anim && typeof anim.finished !== "undefined") {
      anim.finished.then(cleanup).catch(cleanup)
    } else {
      window.setTimeout(cleanup, 650)
    }
  },

  cartStorageKey() {
    return MENU_CART_STORAGE_KEY
  },

  readCartPayload() {
    try {
      const raw = this.el.dataset.cart
      if (!raw) return []
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (_error) {
      return []
    }
  },

  persistCartFromDom() {
    try {
      const cart = this.readCartPayload()
      if (!cart.length) {
        localStorage.removeItem(this.cartStorageKey())
        return
      }
      localStorage.setItem(this.cartStorageKey(), JSON.stringify(cart))
    } catch (_error) {
      // Ignore quota / private-mode failures; cart still works in-session.
    }
  },

  clearPersistedCart() {
    try {
      localStorage.removeItem(this.cartStorageKey())
    } catch (_error) {
      // no-op
    }
  },

  persistMyOrder(number) {
    appendMyOrderNumber(number)
  },

  syncMyOrders(numbers) {
    writeMyOrderNumbers(Array.isArray(numbers) ? numbers : [])
  },

  clearMyOrders() {
    try {
      localStorage.removeItem(MY_ORDERS_STORAGE_KEY)
      localStorage.removeItem(LEGACY_CURRENT_ORDER_STORAGE_KEY)
    } catch (_error) {
      // no-op
    }
  },

  persistLoyaltyPhone(phone) {
    writeLoyaltyPhone(phone)
  },

  clearLoyaltyPhoneStorage() {
    clearLoyaltyPhone()
  },

  ensureLoyaltyPhoneRestored() {
    if (this._loyaltyPhoneRestored) return
    if (!this.el.querySelector("#menu-items")) return

    const phone = readLoyaltyPhone()
    if (!phone) {
      this._loyaltyPhoneRestored = true
      return
    }

    this._loyaltyPhoneRestored = true
    this.pushEvent("restore_loyalty_phone", {phone})
  },

  ensureMyOrdersRestored() {
    const numbers = readMyOrderNumbers()
    if (!numbers.length) return

    // Only restore once the menu browse surface is rendered.
    if (!this.el.querySelector("#menu-items")) return
    if (this.el.querySelector("#menu-qr-my-orders")) return

    this._myOrdersRestoreAttempts = (this._myOrdersRestoreAttempts || 0) + 1
    if (this._myOrdersRestoreAttempts > 5) return

    const now = Date.now()
    if (this._myOrdersRestoreLastAt && now - this._myOrdersRestoreLastAt < 200) return
    this._myOrdersRestoreLastAt = now

    this.pushEvent("restore_my_orders", {numbers})
  },

  restorePersistedCart() {
    if (this._cartRestoreAttempted) return
    this._cartRestoreAttempted = true

    try {
      if (this.readCartPayload().length > 0) return

      const raw = localStorage.getItem(this.cartStorageKey())
      if (!raw) return

      const parsed = JSON.parse(raw)
      if (!Array.isArray(parsed) || parsed.length === 0) {
        this.clearPersistedCart()
        return
      }

      this.pushEvent("restore_cart", {cart: parsed})
    } catch (_error) {
      this.clearPersistedCart()
    }
  },

  scrollBasketTop() {
    const go = () => {
      const body = this.el.querySelector(".menu-basket-body")
      if (body) body.scrollTop = 0
    }
    requestAnimationFrame(() => requestAnimationFrame(go))
  },

  focusMenuSearch() {
    const input = this.el.querySelector("#menu-search-input")
    if (!input) return
    requestAnimationFrame(() => {
      input.focus()
      if (typeof input.select === "function") input.select()
    })
  },

  scrollOffset() {
    const sticky = this.el.querySelector("#menu-qr-sticky")
    if (sticky) return Math.ceil(sticky.getBoundingClientRect().height) + 8

    const chrome =
      this.el.querySelector("#menu-qr-chrome") ||
      this.el.querySelector(".brune-top") ||
      this.el.querySelector(".site-top")
    const rail =
      this.el.querySelector("#menu-craving.menu-craving--sticky") ||
      this.el.querySelector(".brune-menu-tabs-line") ||
      this.el.querySelector(".brune-menu-nav")
    return (chrome?.offsetHeight || 0) + (rail?.offsetHeight || 0) + 8
  },

  scrollTo(top) {
    window.scrollTo({top, behavior: "auto"})
  },

  scrollToItems() {
    this.scrollToMenuContent()
  },

  scrollToMenuContent() {
    const go = () => {
      const target =
        this.el.querySelector("#menu-signature-feature") ||
        this.el.querySelector("#menu-items .brune-menu-section") ||
        this.el.querySelector("#menu-items")
      if (!target) return

      const offset = this.scrollOffset()
      const rectTop = target.getBoundingClientRect().top
      if (rectTop >= offset - 4 && rectTop <= offset + 48) return

      const top = Math.max(0, rectTop + window.scrollY - offset)
      this.scrollTo(top)
    }

    requestAnimationFrame(() => requestAnimationFrame(go))
  },

  scrollToCategory(name) {
    this.scrollToMenuContent()
  },

  scrollActiveChip(id, behavior = "auto") {
    if (!id) return
    const motion = behavior === "smooth" ? "smooth" : "auto"
    const go = () => {
      const chip = this.el.querySelector(`#${CSS.escape(id)}`)
      if (!chip) return
      const rail = chip.closest(".menu-craving-rail")
      if (rail) {
        const railRect = rail.getBoundingClientRect()
        const chipRect = chip.getBoundingClientRect()
        const delta =
          chipRect.left - railRect.left - (railRect.width / 2 - chipRect.width / 2)
        rail.scrollTo({
          left: Math.max(0, rail.scrollLeft + delta),
          behavior: motion
        })
        return
      }
      chip.scrollIntoView({
        inline: "center",
        block: "nearest",
        behavior: motion
      })
    }
    requestAnimationFrame(go)
  }
}

Hooks.MenuSheet = {
  mounted() {
    const sheet = this.el
    const handle = sheet.querySelector("[data-drag-handle]")
    if (!handle) return

    const closeEvent = sheet.dataset.closeEvent || "close_detail"
    const axis = sheet.dataset.dragAxis || "y"
    let start = 0
    let current = 0
    let dragging = false

    const onStart = (value) => {
      start = value
      current = 0
      dragging = true
      sheet.classList.add("is-dragging")
    }

    const onMove = (value) => {
      if (!dragging) return
      current = Math.max(0, value - start)
      if (axis === "x") {
        sheet.style.transform = `translateX(${current}px)`
      } else {
        sheet.style.transform = `translateY(${current}px)`
      }
    }

    const onEnd = () => {
      if (!dragging) return
      dragging = false
      sheet.classList.remove("is-dragging")

      if (current > 110) {
        this.pushEvent(closeEvent, {})
      } else {
        sheet.style.transform = ""
      }

      current = 0
    }

    this._onTouchStart = (e) => onStart(axis === "x" ? e.touches[0].clientX : e.touches[0].clientY)
    this._onTouchMove = (e) => onMove(axis === "x" ? e.touches[0].clientX : e.touches[0].clientY)
    this._onTouchEnd = () => onEnd()
    this._onMouseDown = (e) => {
      onStart(axis === "x" ? e.clientX : e.clientY)
      window.addEventListener("mousemove", this._onMouseMove)
      window.addEventListener("mouseup", this._onMouseUp)
    }
    this._onMouseMove = (e) => onMove(axis === "x" ? e.clientX : e.clientY)
    this._onMouseUp = () => {
      window.removeEventListener("mousemove", this._onMouseMove)
      window.removeEventListener("mouseup", this._onMouseUp)
      onEnd()
    }

    handle.addEventListener("touchstart", this._onTouchStart, {passive: true})
    window.addEventListener("touchmove", this._onTouchMove, {passive: true})
    window.addEventListener("touchend", this._onTouchEnd)
    handle.addEventListener("mousedown", this._onMouseDown)
  },

  destroyed() {
    const handle = this.el.querySelector("[data-drag-handle]")
    if (handle && this._onTouchStart) {
      handle.removeEventListener("touchstart", this._onTouchStart)
      handle.removeEventListener("mousedown", this._onMouseDown)
    }
    window.removeEventListener("touchmove", this._onTouchMove)
    window.removeEventListener("touchend", this._onTouchEnd)
    window.removeEventListener("mousemove", this._onMouseMove)
    window.removeEventListener("mouseup", this._onMouseUp)
  }
}

const keyboardDismissSelector = "[data-dismiss-keyboard]"
const nonTextInputTypes = new Set([
  "button",
  "checkbox",
  "color",
  "file",
  "hidden",
  "image",
  "radio",
  "range",
  "reset",
  "submit"
])
let inputMethodComposing = false

const acceptsVirtualKeyboardInput = element =>
  element instanceof HTMLTextAreaElement ||
  (element instanceof HTMLInputElement && !nonTextInputTypes.has(element.type))

document.addEventListener("compositionstart", () => {
  inputMethodComposing = true
}, true)

document.addEventListener("compositionend", () => {
  inputMethodComposing = false
}, true)

document.addEventListener("pointerdown", event => {
  if (
    inputMethodComposing ||
    event.isPrimary === false ||
    (event.pointerType !== "touch" && event.pointerType !== "pen")
  ) {
    return
  }

  const completionControl =
    event.target instanceof Element
      ? event.target.closest(keyboardDismissSelector)
      : null

  if (
    !completionControl ||
    completionControl.matches(":disabled") ||
    completionControl.getAttribute("aria-disabled") === "true"
  ) {
    return
  }

  const activeElement = document.activeElement
  if (!acceptsVirtualKeyboardInput(activeElement)) return

  activeElement.blur()
}, true)

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits.
// Employee tablet shell: skip the green topbar so POS settle/print does not
// look like a loading screen, and do not dim the page.
const isEmployeeApp = () =>
  document.documentElement?.dataset?.application === "elilai-kafe-employee"

topbar.config({barColors: {0: "#3a8a3e"}, shadowColor: "rgba(58, 138, 62, 0.15)"})
window.addEventListener("phx:page-loading-start", info => {
  if (isEmployeeApp()) return
  topbar.show(200)
  const kind = info.detail?.kind
  if (kind !== "initial" && kind !== "ignore") {
    document.documentElement.classList.add("page-is-loading")
  }
})
window.addEventListener("phx:page-loading-stop", _info => {
  topbar.hide()
  document.documentElement.classList.remove("page-is-loading")
  // Marketing site page-enter animation is intentional; skip on shop tablet.
  if (isEmployeeApp()) return
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  if (reduce) return
  const page = document.querySelector(".site-page")
  if (!page) return
  page.classList.remove("is-entering")
  void page.offsetWidth
  page.classList.add("is-entering")
})

function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return Promise.resolve(null)

  return navigator.serviceWorker.register("/sw.js")
}

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64)
  const output = new Uint8Array(raw.length)

  for (let i = 0; i < raw.length; i += 1) {
    output[i] = raw.charCodeAt(i)
  }

  return output
}

Hooks.OrderPushPrompt = {
  mounted() {
    this.dismissKey = `coffeespot.orderPush.dismissed.${this.el.dataset.orderNumber || ""}`
    this.allowBtn = this.el.querySelector("[data-order-push-allow]")
    this.lede = this.el.querySelector("[data-order-push-lede]")
    this.iosHelp = this.el.querySelector("[data-order-push-ios]")
    this.subscribing = false

    if (this.wasDismissed()) {
      this.el.hidden = true
      return
    }

    if (this.iosNeedsHomeScreen()) {
      this.showIosHelp()
    } else if (!this.pushSupported()) {
      this.el.hidden = true
      return
    }

    this.onAllow = (event) => {
      if (event.type === "touchend") event.preventDefault()
      event.stopPropagation()
      this.subscribe()
    }

    this.allowBtn?.addEventListener("click", this.onAllow)
    this.allowBtn?.addEventListener("touchend", this.onAllow, {passive: false})
    if (!this.iosNeedsHomeScreen()) this.maybeResubscribe()
  },

  destroyed() {
    this.allowBtn?.removeEventListener("click", this.onAllow)
    this.allowBtn?.removeEventListener("touchend", this.onAllow)
  },

  wasDismissed() {
    try {
      return localStorage.getItem(this.dismissKey) === "1"
    } catch (_error) {
      return false
    }
  },

  isStandalonePwa() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    )
  },

  isAppleMobile() {
    const ua = window.navigator.userAgent || ""
    if (/iPhone|iPad|iPod/i.test(ua)) return true
    return window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1
  },

  iosNeedsHomeScreen() {
    return this.isAppleMobile() && !this.isStandalonePwa()
  },

  showIosHelp() {
    if (this.lede) this.lede.hidden = true
    if (this.iosHelp) this.iosHelp.hidden = false
  },

  pushSupported() {
    return (
      "serviceWorker" in navigator &&
      "PushManager" in window &&
      "Notification" in window
    )
  },

  async maybeResubscribe() {
    try {
      const registration = await navigator.serviceWorker.ready
      const existing = await registration.pushManager.getSubscription()
      if (!existing) return
      this.pushSubscription(existing)
    } catch (_error) {
      // Ignore unsupported / permission-denied browsers.
    }
  },

  async subscribe() {
    if (this.subscribing) return
    this.subscribing = true

    try {
      if (this.iosNeedsHomeScreen()) {
        this.showIosHelp()
        if (navigator.share) {
          try {
            await navigator.share({
              title: "CoffeeSpot",
              url: window.location.href
            })
          } catch (_error) {
            // User cancelled the share sheet.
          }
        }
        return
      }

      const permission = await Notification.requestPermission()
      if (permission !== "granted") return

      await registerServiceWorker()
      const registration = await navigator.serviceWorker.ready
      const vapid = (this.el.dataset.vapidPublicKey || "").trim()
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapid)
      })

      this.pushSubscription(subscription)
    } catch (_error) {
      this.showIosHelp()
    } finally {
      this.subscribing = false
    }
  },

  pushSubscription(subscription) {
    const json = subscription.toJSON()
    this.pushEvent("enable_order_push", {
      endpoint: json.endpoint,
      p256dh: json.keys?.p256dh,
      auth: json.keys?.auth
    })
  }
}

function registerEmployeeServiceWorker() {
  registerServiceWorker()
}

const syncMenuChromeInset = () => {
  const vv = window.visualViewport
  const bottom = vv ? Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop)) : 0
  document.documentElement.style.setProperty("--menu-chrome-bottom", `${bottom}px`)
}

syncMenuChromeInset()
window.addEventListener("resize", syncMenuChromeInset)
if (window.visualViewport) {
  window.visualViewport.addEventListener("resize", syncMenuChromeInset)
  window.visualViewport.addEventListener("scroll", syncMenuChromeInset)
}

// connect if there are any LiveViews on the page
liveSocket.connect()
registerEmployeeServiceWorker()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
