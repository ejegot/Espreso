# Repository guide

## Build, test, and format

The main application is an Elixir/Phoenix project backed by PostgreSQL. From the repository root:

```sh
mix setup                   # Fetch dependencies, create/migrate the DB, seed, build assets
mix phx.server              # Start Phoenix at localhost:4000
mix test                    # Create/migrate the test DB, then run ExUnit
mix test test/espreso/menu_test.exs
mix test test/espreso/menu_test.exs:42  # Run one test at a line
mix format --check-formatted
mix assets.build            # Build development CSS and JavaScript
mix assets.deploy            # Minify and digest production assets
```

`mix test` needs PostgreSQL available at the test settings in `config/test.exs`. JavaScript printer-bridge tests run with `node assets/js/elilai_printer_bridge_test.mjs`. For the Capacitor app, run commands from `apps/elilai-kafe-app`:

```sh
npm install
npx cap sync android
npm run build:android:debug
```

Android Java unit tests can be run from `apps/elilai-kafe-app/android` with `./gradlew testDebugUnitTest`; select one class with `./gradlew testDebugUnitTest --tests 'ph.elilai.kafe.printer.EscPosTcpClientTest'`. Release and iOS build requirements are documented in `apps/elilai-kafe-app/README.md`. The separate Flutter printer hardware prototype is documented in `apps/printer_spike/README.md`.

## Architecture

- `lib/espreso/` contains Ecto-backed business contexts and schemas (orders, menu, accounts, shifts, payments, loyalty, tenancy, printer, and related domains). Keep business rules and persistence operations in these contexts rather than duplicating them in web handlers.
- `lib/espreso_web/` contains the Phoenix boundary: `router.ex` defines browser/API routes and their pipelines; controllers serve HTTP/API actions; LiveViews implement the staff and customer interfaces; components and layouts provide shared UI.
- Staff authorization is enforced through router pipelines and LiveView `on_mount` hooks in `EspresoWeb.StaffAuth`. API authorization uses separate plugs and permission-specific pipelines. When adding a route, follow the corresponding existing authenticated or public route pattern.
- Tenant and branch selection is request/process scoped through `Espreso.Tenancy.put_context/1`. Domain queries and inserted records use the active tenant/branch; `current_ids/0` falls back to CoffeeSpot/Lilac. Preserve tenant and branch scoping when adding or changing queries, writes, and tests.
- `assets/` is bundled into the Phoenix app by esbuild and Tailwind. The Capacitor app under `apps/elilai-kafe-app/` is a thin native shell that loads the deployed Phoenix LiveView app; the web app remains the UI and business-logic source of truth.
- For native printer dispatch, Phoenix constructs ESC/POS payloads. With the `:native_client` transport the tablet's Capacitor bridge sends them over the shop LAN directly to the printer; the cloud server must not open a connection to a shop-local printer. The bridge implementation is in `assets/js/`, native plugin code in the Capacitor Android app, and transport coordination in `lib/espreso/printer*` and `lib/espreso_web/`.

## Repository conventions

- Follow the existing domain-context boundary: LiveViews/controllers handle web interaction and call domain contexts for business operations; share rules in the context rather than duplicating them between UI and API paths.
- Tenant context is stored per process. Set the intended context for non-request work and tests, and use tenant/branch scopes instead of assuming the fallback tenant.
- Test data setup in `test/support/data_case.ex` establishes CoffeeSpot/Lilac and opens the shop day by default. Use `without_shop_open: true` when the test specifically exercises closed-shop behavior; use the existing `DataCase`, `ConnCase`, `ApiCase`, or `ChannelCase` matching the test boundary.
- Keep native-shell changes aligned with `apps/elilai-kafe-app/README.md` and `docs/SHOP_TABLET_PERFORMANCE.md`. The shell loads remote Phoenix pages; avoid introducing a second frontend or blocking the WebView UI thread.
- The existing Cursor rule `.cursor/rules/git-branch-no-linear.mdc` is also repository guidance: do not wait for a Linear issue; implementation branches use `ej/<short-kebab-slug>` without invented ticket numbers. The user handles add/commit/push/merge; open a PR only when asked, and create GitHub issues only when asked.

## Critical behavior safeguards

- Treat POS order transitions, cash/GCash/Maya payment handling, PayMongo webhooks, loyalty-point accounting, staff authorization, and printer/drawer actions as production-critical behavior. Preserve their existing invariants and flows; make minimal, focused changes and test affected paths.
- Before editing, inspect `git status` and preserve unrelated user changes. Run relevant tests and report their exact results.
- Never deploy, run production migrations, modify production data, or perform irreversible operations without explicit user approval.
