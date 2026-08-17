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
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
