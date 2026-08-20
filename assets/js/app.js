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

Hooks.MenuBrowse = {
  mounted() {
    this.handleEvent("scroll_to_items", () => this.scrollToItems())
    this.handleEvent("scroll_to_category", ({name}) => this.scrollToCategory(name))
  },

  scrollOffset() {
    const header = this.el.querySelector(".brune-top") || this.el.querySelector(".site-top")
    const nav = this.el.querySelector(".brune-menu-tabs-line") || this.el.querySelector(".brune-menu-nav")
    return (header?.offsetHeight || 0) + (nav?.offsetHeight || 0) + 12
  },

  scrollTo(top) {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const event = new CustomEvent("site:scroll-to", {detail: {top, reduce}, cancelable: true})
    window.dispatchEvent(event)
    if (!event.defaultPrevented) {
      window.scrollTo({top, behavior: reduce ? "auto" : "smooth"})
    }
  },

  scrollToItems() {
    const items = this.el.querySelector("#menu-items")
    if (!items) return
    const top = Math.max(0, items.getBoundingClientRect().top + window.scrollY - this.scrollOffset())
    requestAnimationFrame(() => this.scrollTo(top))
  },

  scrollToCategory(name) {
    const go = () => {
      const section = this.el.querySelector(`#category-${name}`)
      const title = section?.querySelector(".brune-menu-category-title")
      const target = title || section
      if (!target) return this.scrollToItems()

      const top = Math.max(0, target.getBoundingClientRect().top + window.scrollY - this.scrollOffset())
      this.scrollTo(top)
    }

    requestAnimationFrame(() => requestAnimationFrame(go))
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
