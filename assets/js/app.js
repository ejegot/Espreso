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

Hooks.LandingCarousel = {
  mounted() {
    this.carousel = this.el
    this.root = this.el.closest("#menu-landing")
    this.dots = this.root ? Array.from(this.root.querySelectorAll("[data-landing-dot]")) : []
    this.onScroll = () => this.syncDots()
    this.carousel.addEventListener("scroll", this.onScroll, {passive: true})
    this.dotHandlers = this.dots.map((dot) => {
      const handler = () => this.scrollToIndex(Number(dot.dataset.landingDot || 0))
      dot.addEventListener("click", handler)
      return {dot, handler}
    })
    this.syncDots()
  },

  updated() {
    this.syncDots()
  },

  destroyed() {
    if (this.carousel && this.onScroll) {
      this.carousel.removeEventListener("scroll", this.onScroll)
    }
    if (this.dotHandlers) {
      this.dotHandlers.forEach(({dot, handler}) => dot.removeEventListener("click", handler))
    }
  },

  scrollToIndex(index) {
    const width = this.carousel.clientWidth
    if (!width) return
    this.carousel.scrollTo({left: width * index, behavior: "smooth"})
  },

  syncDots() {
    const width = this.carousel.clientWidth || 1
    const index = Math.max(0, Math.min(this.dots.length - 1, Math.round(this.carousel.scrollLeft / width)))

    this.dots.forEach((dot, dotIndex) => {
      const active = dotIndex === index
      dot.classList.toggle("is-active", active)
      dot.setAttribute("aria-selected", active ? "true" : "false")
    })
  }
}

Hooks.MenuBrowse = {
  mounted() {
    this.handleEvent("scroll_to_items", () => this.scrollToItems())
    this.handleEvent("scroll_to_category", ({name}) => this.scrollToCategory(name))
    this.handleEvent("scroll_to_menu_content", () => this.scrollToMenuContent())
    this.handleEvent("scroll_active_chip", ({id}) => this.scrollActiveChip(id))
    this.handleEvent("scroll_basket_top", () => this.scrollBasketTop())
    this.handleEvent("focus_menu_search", () => this.focusMenuSearch())
    this.handleEvent("clear_persisted_cart", () => this.clearPersistedCart())
    this.handleEvent("persist_my_order", ({number}) => this.persistMyOrder(number))
    this.handleEvent("persist_current_order", ({number}) => this.persistMyOrder(number))
    this.handleEvent("sync_my_orders", ({numbers}) => this.syncMyOrders(numbers))
    this.handleEvent("clear_my_orders", () => this.clearMyOrders())
    this.handleEvent("clear_current_order", () => this.clearMyOrders())

    this.onChipClick = (event) => {
      const chip = event.target.closest(".menu-craving-chip")
      if (chip instanceof HTMLElement) chip.blur()
    }

    this.el.addEventListener("click", this.onChipClick)
    this.restorePersistedCart()
    requestAnimationFrame(() => requestAnimationFrame(() => this.ensureMyOrdersRestored()))
    this.persistCartFromDom()
  },

  updated() {
    this.persistCartFromDom()
    this.ensureMyOrdersRestored()
  },

  destroyed() {
    if (this.onChipClick) this.el.removeEventListener("click", this.onChipClick)
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

  scrollActiveChip(id) {
    if (!id) return
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
          behavior: "auto"
        })
        return
      }
      chip.scrollIntoView({
        inline: "center",
        block: "nearest",
        behavior: "auto"
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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#3a8a3e"}, shadowColor: "rgba(58, 138, 62, 0.15)"})
window.addEventListener("phx:page-loading-start", info => {
  topbar.show(200)
  const kind = info.detail?.kind
  if (kind !== "initial" && kind !== "ignore") {
    document.documentElement.classList.add("page-is-loading")
  }
})
window.addEventListener("phx:page-loading-stop", _info => {
  topbar.hide()
  document.documentElement.classList.remove("page-is-loading")
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  if (reduce) return
  const page = document.querySelector(".site-page")
  if (!page) return
  page.classList.remove("is-entering")
  void page.offsetWidth
  page.classList.add("is-entering")
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
