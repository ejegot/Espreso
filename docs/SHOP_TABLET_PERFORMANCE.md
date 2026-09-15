# Shop tablet performance / responsiveness

**Scope:** ELIlai Kafe Android app (`ph.elilai.kafe`) + employee LiveView shell.  
**Status:** Explicit product requirement. Do not deploy from this doc alone.

## Requirement

This is a production shop app. Responsiveness is a core requirement.

### Goals

- App startup should feel fast.
- Login screen should appear without an unnecessary blocking loading screen.
- Staff search/select must respond immediately.
- PIN keypad taps must feel instant.
- Home/POS buttons must respond immediately.
- POS item taps and cart interactions must feel immediate.
- Hamburger navigation must open/close immediately.
- Normal LiveView navigation should not introduce unnecessary loading states.
- Do not add artificial splash/loading screens.
- Do not block the WebView UI thread.

### Loading UI policy

Do **not** simply remove legitimate loading states.

Use loading/progress UI only when an actual asynchronous operation is in progress, such as:

- network request
- payment transition
- printer operation
- native bridge operation

Physical printer/drawer operations **must not** freeze the WebView or block touch input. The native Android printer bridge must perform TCP/network operations off the UI thread and return the result asynchronously.

### Change discipline

- First identify measurable/obvious performance problems.
- Fix only justified issues.
- Preserve existing business logic and UX.
- Do **not** perform a broad rewrite or speculative optimization.
- Do **not** change: Pass 3E-4 payment/concurrency, loyalty rules, sales attribution, GCash/Maya semantics, existing authorization rules.

## Inspection checklist (obvious causes)

- unnecessary full-page loading states
- blocking JavaScript
- synchronous native operations
- unnecessary repeated LiveView requests
- excessive DOM work
- unnecessary polling/timers
- oversized assets loaded at startup
- duplicate event listeners
- navigation that waits on unrelated work

## Pass notes (2026-09-15)

### 1. What caused observed / likely slowness

| Cause | Why it matters |
| --- | --- |
| Global `html.page-is-loading .site-page { pointer-events: none; opacity: 0.55 }` on LiveView navigations | Every non-initial LiveView nav dimmed the page and **blocked all taps** until `page-loading-stop`. Felt like a frozen tablet during Home ↔ POS ↔ Orders. |
| Forced `.site-page.is-entering` + reflow on every `phx:page-loading-stop` | Re-ran a 0.55s opacity enter animation after each nav; made post-navigation UI feel laggy. |
| Blocking Google Fonts stylesheet in `employee_root` | Render-blocking remote CSS delayed first paint / login appearance on cold start. |
| Android `Theme.SplashScreen` | OS launch splash only — not an in-app loader; left as-is. |
| Printer TCP | Already off UI thread via `ExecutorService` in `EscPosPrinterPlugin` — not a UI freeze source when bridge is used correctly. |

### 2. What was changed

- **Employee LiveView nav:** skip adding `page-is-loading` for `data-application="elilai-kafe-employee"`; keep topbar for real async progress (`assets/js/app.js`).
- **Employee CSS:** disable marketing page-enter animation; ensure `page-is-loading` never disables pointer-events on the employee shell (`assets/css/app.css`).
- **Employee fonts:** preload + non-blocking stylesheet load (`employee_root.html.heex`).
- **Docs:** this file + README section making the requirement explicit.

### 3. Intentionally left unchanged

- Pass 3E-4 payment / concurrency / physical coordinator semantics
- Loyalty, sales attribution, GCash/Maya payment rules, authorization
- PIN submit `is-loading` (real auth network round-trip)
- Topbar progress during LiveView/network work
- Native printer bridge async design (already correct)
- Android OS splash theme
- Service worker registration behavior
- SmoothScroll hook (coarse pointers already short-circuit heavy RAF path)
- Marketing public site page transitions / `page-is-loading` behavior

### 4. Remaining performance limitations

- LiveView round-trips still depend on network latency to Fly (or LAN Phoenix).
- First cold start still downloads `app.css` / `app.js` and connects the LiveView socket.
- Google Fonts still load from the network (async now; brief fallback fonts possible).
- Large POS catalogs / DOM size can still cost paint time; not rewritten here.
- Printer/drawer completion still waits on TCP to the HS-802UL (async; UI stays interactive).

### 5. Manual tablet test steps

1. **Startup:** Cold-launch the APK. Confirm OS splash is brief, then login appears without an extra full-screen in-app loader.
2. **Typing / search:** On login, type in staff search; characters and filtered list should update immediately (no page dim, no blocked taps).
3. **PIN:** Tap keypad digits rapidly; each tap should update the PIN UI instantly. Only Continue/submit may show a real loading state while auth runs.
4. **Navigation:** After login, tap Home → POS → Orders → Home. UI must stay tappable; topbar may flash for network; no dimmed/frozen full page.
5. **Hamburger:** Open/close drawer repeatedly; must be immediate (checkbox/CSS drawer, no wait).
6. **POS:** Add items, change qty, remove line — taps should feel immediate; only payment/printer flows may show progress for real async work.
7. **Printer:** Trigger receipt/drawer (cash path). Confirm WebView remains responsive while print/drawer runs; no frozen touch surface during TCP.

Do not deploy until explicitly requested.
