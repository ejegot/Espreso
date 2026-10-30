defmodule EspresoWeb.StaffShiftCloseLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.User
  alias Espreso.CashOuts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.PettyCash
  alias Espreso.Printer
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Shifts.can_access_close?(user) do
      {:ok, assign_close_state(socket), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to close shift.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("validate", %{"close" => params}, socket) do
    if socket.assigns.blocked? do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:counted_cash, Map.get(params, "counted_cash", ""))
       |> assign(:petty_cash_counted, Map.get(params, "petty_cash_counted", ""))
       |> assign(:notes, Map.get(params, "notes", ""))
       |> assign(:petty_cash_notes, Map.get(params, "petty_cash_notes", ""))
       |> assign(:confirming?, false)
       |> assign(:form_error, nil)}
    end
  end

  def handle_event("prepare_close", %{"close" => params}, socket) do
    if socket.assigns.blocked? do
      {:noreply, socket}
    else
      counted = Map.get(params, "counted_cash", "") |> to_string() |> String.trim()

      petty_counted =
        Map.get(params, "petty_cash_counted", "") |> to_string() |> String.trim()

      petty_notes = Map.get(params, "petty_cash_notes", "") |> to_string() |> String.trim()

      cond do
        counted == "" ->
          {:noreply,
           socket
           |> assign(:counted_cash, counted)
           |> assign(:petty_cash_counted, petty_counted)
           |> assign(:notes, Map.get(params, "notes", ""))
           |> assign(:petty_cash_notes, petty_notes)
           |> assign(:confirming?, false)
           |> assign(:form_error, "Enter the actual cash in the drawer.")}

        petty_counted == "" ->
          {:noreply,
           socket
           |> assign(:counted_cash, counted)
           |> assign(:petty_cash_counted, petty_counted)
           |> assign(:notes, Map.get(params, "notes", ""))
           |> assign(:petty_cash_notes, petty_notes)
           |> assign(:confirming?, false)
           |> assign(:form_error, "Count the petty cash before recording the close.")}

        is_nil(parse_display_decimal(petty_counted)) ->
          {:noreply,
           socket
           |> assign(:counted_cash, counted)
           |> assign(:petty_cash_counted, petty_counted)
           |> assign(:notes, Map.get(params, "notes", ""))
           |> assign(:petty_cash_notes, petty_notes)
           |> assign(:confirming?, false)
           |> assign(:form_error, "Enter a valid non-negative petty-cash count.")}

        petty_cash_variance(petty_counted, socket.assigns.petty_cash_expected) != nil and
          not Decimal.equal?(
            petty_cash_variance(petty_counted, socket.assigns.petty_cash_expected),
            0
          ) and petty_notes == "" ->
          {:noreply,
           socket
           |> assign(:counted_cash, counted)
           |> assign(:petty_cash_counted, petty_counted)
           |> assign(:notes, Map.get(params, "notes", ""))
           |> assign(:petty_cash_notes, petty_notes)
           |> assign(:confirming?, false)
           |> assign(:form_error, "Add a reason when petty cash is over or short.")}

        true ->
          {:noreply,
           socket
           |> assign(:counted_cash, counted)
           |> assign(:petty_cash_counted, petty_counted)
           |> assign(:notes, Map.get(params, "notes", ""))
           |> assign(:petty_cash_notes, petty_notes)
           |> assign(:confirming?, true)
           |> assign(:form_error, nil)}
      end
    end
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirming?, false)}
  end

  def handle_event("record_close", _params, socket) do
    if socket.assigns.blocked? do
      {:noreply, assign_close_state(socket)}
    else
      params = %{
        "counted_cash" => socket.assigns.counted_cash,
        "notes" => socket.assigns.notes,
        "petty_cash_counted" => socket.assigns.petty_cash_counted,
        "petty_cash_notes" => socket.assigns.petty_cash_notes
      }

      case Shifts.record_close(socket.assigns.current_user, params) do
        {:ok, close} ->
          staff_shift_ended? = barista?(socket.assigns.current_user)

          {:noreply,
           socket
           |> put_flash(:info, close_success_flash(staff_shift_ended?))
           |> assign(:close, close)
           |> assign(:already_closed?, true)
           |> assign(:blocked?, false)
           |> assign(:staff_shift_ended?, staff_shift_ended?)
           |> assign(:confirming?, false)
           |> assign(:form_error, nil)
           |> reset_close_history()}

        {:error, :already_closed} ->
          {:noreply,
           socket
           |> assign(:close, Shifts.get_todays_close())
           |> assign(:already_closed?, true)
           |> assign(:blocked?, false)
           |> assign(:confirming?, false)
           |> assign(:form_error, "Shift already closed for today.")
           |> reset_close_history()}

        {:error, :other_staff_active} ->
          {:noreply,
           socket
           |> assign_close_state()
           |> assign(:form_error, other_staff_message())}

        {:error, :not_on_shift} ->
          {:noreply,
           socket
           |> assign_close_state()
           |> assign(
             :form_error,
             "You need an open staff shift to close the shop as barista."
           )}

        {:error, :unauthorized} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don’t have access to close shift.")
           |> push_navigate(to: ~p"/staff")}

        {:error, :counted_cash_required} ->
          {:noreply,
           socket
           |> assign(:confirming?, false)
           |> assign(:form_error, "Enter the actual cash in the drawer.")}

        {:error, :petty_cash_notes_required} ->
          {:noreply,
           socket
           |> assign(:confirming?, false)
           |> assign(:form_error, "Add a reason when petty cash is over or short.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:confirming?, false)
           |> assign(:form_error, close_changeset_error(changeset))}
      end
    end
  end

  def handle_event("load_more_close_history", _params, socket) do
    {:noreply, append_close_history(socket)}
  end

  def handle_event("toggle_history", %{"date" => date}, socket) do
    open = if socket.assigns.history_open == date, do: nil, else: date
    {:noreply, assign(socket, :history_open, open)}
  end

  def handle_event("print_day_report", params, socket) do
    close = printable_close(socket, params)

    if is_nil(close) do
      {:noreply, assign(socket, :printer_note, "No sealed close to print.")}
    else
      staff_name = socket.assigns.current_user.name

      case Printer.dispatch_day_report(close, staff_name: staff_name) do
        {:client_dispatch, bytes} ->
          {:noreply,
           socket
           |> assign(:printer_note, "Sending day report…")
           |> push_event("elilai-printer", %{
             action: "raw_test",
             permit: "raw",
             request_id: Integer.to_string(System.unique_integer([:positive])),
             data_base64: Printer.encode_payload(bytes),
             order_id: 0,
             flow: "day_report"
           })}

        :dispatched ->
          {:noreply, assign(socket, :printer_note, "Day report sent to printer.")}

        :disabled ->
          {:noreply, assign(socket, :printer_note, "Printer is disabled.")}

        {:definite_failure, reason} ->
          {:noreply, assign(socket, :printer_note, "Print failed (#{inspect(reason)}).")}

        {:uncertain, reason} ->
          {:noreply,
           assign(socket, :printer_note, "Print outcome uncertain (#{inspect(reason)}).")}

        other ->
          {:noreply, assign(socket, :printer_note, "Print failed (#{inspect(other)}).")}
      end
    end
  end

  def handle_event(
        "elilai_printer_result",
        %{"flow" => "day_report", "ok" => ok} = params,
        socket
      ) do
    ok? = ok in [true, "true"]

    note =
      if ok?,
        do: "Day report printed.",
        else: "Print failed (#{Map.get(params, "error") || "failed"})."

    {:noreply, assign(socket, :printer_note, note)}
  end

  def handle_event("elilai_printer_result", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    shop_date = close_shop_date(assigns)
    cash_total = open_cash_total(assigns)
    snapshot_rows = closed_via_rows(assigns[:close])
    snapshot_cash = snapshot_cash_total(assigns[:close])
    opening_cash = assigns[:opening_cash_amount]
    petty_transfer = petty_cash_transfer(assigns[:petty_cash_counted], assigns[:petty_cash_total])

    expected_cash =
      Shifts.expected_drawer_cash(
        opening_cash,
        Shifts.cash_sales_total(assigns[:breakdown]),
        assigns[:cash_out_total],
        petty_transfer
      )

    live_variance = live_variance(assigns[:counted_cash], expected_cash)

    petty_cash_variance =
      petty_cash_variance(assigns[:petty_cash_counted], assigns[:petty_cash_expected])

    petty_cash_transfer_preview = petty_cash_transfer_preview(assigns[:petty_cash_counted])

    assigns =
      assigns
      |> assign(:shop_date, shop_date)
      |> assign(:cash_total, cash_total)
      |> assign(:snapshot_rows, snapshot_rows)
      |> assign(:snapshot_cash, snapshot_cash)
      |> assign(:opening_cash, opening_cash)
      |> assign(:expected_cash, expected_cash)
      |> assign(:live_variance, live_variance)
      |> assign(:petty_cash_variance, petty_cash_variance)
      |> assign(:petty_cash_transfer_preview, petty_cash_transfer_preview)

    ~H"""
    <.staff_shell current={:close} current_user={@current_user} page_title="Close Shop" chrome={:bar}>
      <main class="staff-home-main staff-shift-close" id="staff-shift-close">
        <header class="staff-shift-close-head">
          <p class="staff-shift-close-scope">
            <span
              class={[
                "staff-shift-close-status",
                @already_closed? && "staff-shift-close-status--closed",
                @blocked? && "staff-shift-close-status--blocked"
              ]}
              id="staff-shift-close-status"
            >
              <%= cond do %>
                <% @already_closed? -> %>
                  Shift closed
                <% @block_reason == :other_staff_active -> %>
                  Waiting on staff
                <% @blocked? -> %>
                  Not ready
                <% true -> %>
                  Open
              <% end %>
            </span>
            <span class="staff-shift-close-scope-date">
              {Calendar.strftime(@shop_date, "%b %d")}
            </span>
          </p>
          <p class="staff-shift-close-lede">
            <%= cond do %>
              <% @already_closed? -> %>
                Sealed snapshot of today’s settled sales and the drawer cash count that was recorded.
              <% @block_reason == :other_staff_active -> %>
                Another staff member is still on shift. They need to Time Out before you can Close Shop.
              <% @block_reason == :not_on_shift -> %>
                You need an open staff shift to close the shop. Log in again if your shift already ended.
              <% true -> %>
                Count petty cash first, move the amount shown between the petty box and drawer, then count the drawer and seal the day.
                System paid totals are settled sales — not a physical cash target.
            <% end %>
          </p>
        </header>

        <%= if @already_closed? and @close do %>
          <section
            class="staff-shift-close-done"
            id="staff-shift-close-done"
            role="status"
            aria-label="Sealed shift close"
          >
            <div class="staff-shift-close-seal">
              <p class="staff-shift-close-done-badge">Shift closed</p>
              <p class="staff-shift-close-done-copy" id="staff-shift-close-done-meta">
                Closed at {Shifts.format_closed_at(@close.closed_at)}
                <span :if={@close.closed_by_user}>by {@close.closed_by_user.name}</span>
              </p>
              <p
                :if={@staff_shift_ended?}
                class="staff-shift-close-timed-out"
                id="staff-shift-close-timed-out"
              >
                Your staff shift has ended (Time Out). You are still signed in — log out when you are done.
              </p>
              <p class="staff-shift-close-seal-note">
                These are the numbers sealed when this shift was closed.
              </p>
            </div>

            <div class="staff-shift-close-cash" id="staff-shift-close-sealed-cash">
              <p class="staff-shift-close-section-label">Cash settled</p>
              <p class="staff-shift-close-cash-value">{Menu.format_price(@snapshot_cash)}</p>
              <p class="staff-shift-close-section-hint">Cash payments sealed in this close.</p>
            </div>

            <section
              class="staff-shift-close-cash-outs"
              id="staff-shift-close-sealed-cash-outs"
              aria-label="Cash outs"
            >
              <p class="staff-shift-close-section-label">Cash Outs</p>
              <p class="staff-shift-close-cash-value" id="staff-shift-close-sealed-cash-out-total">
                {Menu.format_price(@cash_out_total)}
              </p>
              <p class="staff-shift-close-section-hint">
                Drawer withdrawals recorded for this shop day (non-voided).
              </p>
              <ul
                :if={@cash_outs != []}
                class="staff-shift-close-cash-out-list"
                id="staff-shift-close-sealed-cash-out-list"
              >
                <li :for={entry <- @cash_outs} class="staff-shift-close-cash-out-row">
                  <span class="staff-shift-close-cash-out-amount">
                    {Menu.format_price(entry.amount)}
                  </span>
                  <span class="staff-shift-close-cash-out-category">{entry.category}</span>
                  <span :if={entry.note} class="staff-shift-close-cash-out-note">{entry.note}</span>
                </li>
              </ul>
              <p :if={@cash_outs == []} class="staff-shift-close-section-hint">
                No Cash Outs recorded for this shop day.
              </p>
            </section>

            <div class="staff-shift-close-counted-display" id="staff-shift-close-sealed-drawer">
              <p class="staff-shift-close-section-label">Drawer</p>
              <p class="staff-shift-close-section-hint">
                Opening {drawer_money(@close.opening_cash)} · expected {drawer_money(
                  @close.expected_cash
                )}
              </p>
              <p class="staff-shift-close-cash-value" id="staff-shift-close-sealed-counted">
                {drawer_money(@close.counted_cash)}
              </p>
              <p class="staff-shift-close-section-hint" id="staff-shift-close-sealed-variance">
                {variance_copy(@close.variance)}
              </p>
            </div>

            <div
              :if={!is_nil(@close.petty_cash_counted)}
              class="staff-shift-close-counted-display"
              id="staff-shift-close-sealed-petty-cash"
            >
              <p class="staff-shift-close-section-label">Petty cash</p>
              <p class="staff-shift-close-section-hint">
                Counted before refill {drawer_money(@close.petty_cash_counted)} · expected before refill {drawer_money(
                  @close.petty_cash_expected
                )}
              </p>
              <p class="staff-shift-close-cash-value" id="staff-shift-close-sealed-petty-transfer">
                <%= if Decimal.compare(@close.petty_cash_transfer || Decimal.new("0"), 0) == :gt do %>
                  Refilled from drawer {Menu.format_price(@close.petty_cash_transfer)}
                <% else %>
                  Returned to drawer {Menu.format_price(
                    Decimal.abs(@close.petty_cash_transfer || Decimal.new("0"))
                  )}
                <% end %>
              </p>
              <p
                :if={@close.petty_cash_variance && !Decimal.equal?(@close.petty_cash_variance, 0)}
                class="staff-shift-close-section-hint"
              >
                {variance_copy(@close.petty_cash_variance)} · {@close.petty_cash_notes}
              </p>
            </div>

            <p
              :if={@printer_note}
              class="staff-shift-close-section-hint"
              id="staff-shift-close-print-note"
            >
              {@printer_note}
            </p>

            <section class="staff-shift-close-panel staff-shift-close-panel--secondary">
              <p class="staff-shift-close-section-label">Payment methods</p>
              <ul class="staff-paid-breakdown" id="staff-shift-close-sealed-breakdown">
                <li :for={row <- @snapshot_rows} class="staff-paid-breakdown-row">
                  <span class="staff-paid-breakdown-label">{row.label}</span>
                  <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                  <span class="staff-paid-breakdown-count">{row.count}</span>
                </li>
              </ul>
            </section>

            <div class="staff-shift-close-system" id="staff-shift-close-sealed-system">
              <p class="staff-shift-close-section-label">System paid</p>
              <p class="staff-shift-close-system-value">
                {Menu.format_price(@close.system_total)}
                <span>({@close.system_count} orders)</span>
              </p>
              <p class="staff-shift-close-section-hint">
                Total settled sales sealed for this shop day.
              </p>
            </div>

            <p
              :if={@close.notes}
              class="staff-shift-close-done-notes"
              id="staff-shift-close-sealed-notes"
            >
              {@close.notes}
            </p>

            <div class="staff-shift-close-nav">
              <button
                :if={Printer.enabled?()}
                type="button"
                class="staff-shift-close-submit"
                id="staff-shift-close-print"
                phx-click="print_day_report"
              >
                Print day report
              </button>
              <.link
                :if={@staff_shift_ended?}
                href={~p"/logout"}
                method="delete"
                class="staff-shift-close-submit"
                id="staff-shift-close-logout"
              >
                Log out
              </.link>
              <.link navigate={~p"/staff"} class="staff-shell-tool">Back to Home</.link>
              <.link navigate={~p"/transactions"} class="staff-shell-tool staff-shell-tool--quiet">
                View Transactions
              </.link>
            </div>
          </section>
        <% else %>
          <div class="staff-shift-close-desk">
            <section
              :if={@blocked?}
              class="staff-shift-close-blocked"
              id="staff-shift-close-blocked"
              role="status"
            >
              <p class="staff-shift-close-blocked-title">Cannot close yet</p>
              <p class="staff-shift-close-blocked-copy" id="staff-shift-close-blocked-copy">
                <%= if @block_reason == :not_on_shift do %>
                  You need an open staff shift to close the shop. Log in again if your shift already ended.
                <% else %>
                  Another staff member is still on shift. They need to Time Out before you can Close Shop.
                <% end %>
              </p>
              <ul
                :if={@other_active_names != []}
                class="staff-shift-close-blocked-list"
                id="staff-shift-close-blocked-staff"
              >
                <li :for={name <- @other_active_names}>{name}</li>
              </ul>
              <div class="staff-shift-close-nav">
                <.link navigate={~p"/staff"} class="staff-shell-tool">Back to Home</.link>
              </div>
            </section>

            <section
              :if={!@blocked?}
              class="staff-shift-close-cash-outs"
              id="staff-shift-close-petty-cash"
              aria-label="Petty cash purchases"
            >
              <p class="staff-shift-close-section-label">Petty-cash purchases</p>
              <p class="staff-shift-close-cash-value" id="staff-shift-close-petty-cash-total">
                {Menu.format_price(@petty_cash_total)}
              </p>
              <p class="staff-shift-close-section-hint">
                Paid from the separate float. Refill is recorded as a drawer transfer, not another expense.
              </p>
              <ul
                :if={@petty_cash_entries != []}
                class="staff-shift-close-cash-out-list"
                id="staff-shift-close-petty-cash-list"
              >
                <li :for={entry <- @petty_cash_entries} class="staff-shift-close-cash-out-row">
                  <span class="staff-shift-close-cash-out-amount">
                    {Menu.format_price(entry.amount)}
                  </span>
                  <span class="staff-shift-close-cash-out-category">{entry.category}</span>
                  <span class="staff-shift-close-cash-out-note">{entry.note}</span>
                </li>
              </ul>
              <p :if={@petty_cash_entries == []} class="staff-shift-close-section-hint">
                No petty-cash purchases recorded today.
              </p>
            </section>

            <section
              :if={!@blocked?}
              class="staff-shift-close-cash"
              id="staff-shift-close-cash"
              aria-label="Cash settled"
            >
              <p class="staff-shift-close-section-label">Cash settled</p>
              <p class="staff-shift-close-cash-value">{Menu.format_price(@cash_total)}</p>
              <p class="staff-shift-close-section-hint">Cash payments recorded as paid today.</p>
            </section>

            <section
              :if={!@blocked?}
              class="staff-shift-close-cash-outs"
              id="staff-shift-close-cash-outs"
              aria-label="Cash outs"
            >
              <p class="staff-shift-close-section-label">Cash Outs</p>
              <p class="staff-shift-close-cash-value" id="staff-shift-close-cash-out-total">
                {Menu.format_price(@cash_out_total)}
              </p>
              <p class="staff-shift-close-section-hint">
                Drawer withdrawals recorded today (non-voided).
              </p>
              <ul
                :if={@cash_outs != []}
                class="staff-shift-close-cash-out-list"
                id="staff-shift-close-cash-out-list"
              >
                <li :for={entry <- @cash_outs} class="staff-shift-close-cash-out-row">
                  <span class="staff-shift-close-cash-out-amount">
                    {Menu.format_price(entry.amount)}
                  </span>
                  <span class="staff-shift-close-cash-out-category">{entry.category}</span>
                  <span :if={entry.note} class="staff-shift-close-cash-out-note">{entry.note}</span>
                </li>
              </ul>
              <p :if={@cash_outs == []} class="staff-shift-close-section-hint">
                No Cash Outs recorded today.
              </p>
            </section>

            <section
              :if={!@blocked?}
              class="staff-shift-close-cash"
              id="staff-shift-close-drawer"
              aria-label="Drawer expected"
            >
              <p class="staff-shift-close-section-label">Expected drawer</p>
              <p class="staff-shift-close-cash-value">{Menu.format_price(@expected_cash)}</p>
              <p
                :if={@missing_opening?}
                class="staff-shift-close-section-hint"
                id="staff-shift-close-opening-gap"
              >
                Opening cash was not recorded. Expected uses ₱0 opening.
              </p>
              <p :if={!@missing_opening?} class="staff-shift-close-section-hint">
                Opening {Menu.format_price(@opening_cash)} + cash sales − drawer Cash Outs − petty-cash refill.
              </p>
            </section>

            <form
              :if={!@blocked?}
              id="staff-shift-close-form"
              phx-change="validate"
              phx-submit="prepare_close"
              class="staff-shift-close-form"
            >
              <div class="staff-shift-close-entry">
                <label class="staff-shift-close-field" id="staff-shift-close-petty-counted-field">
                  <span>Count petty cash before refill</span>
                  <div class="staff-shift-close-input-wrap">
                    <span class="staff-shift-close-currency" aria-hidden="true">₱</span>
                    <input
                      type="text"
                      name="close[petty_cash_counted]"
                      value={@petty_cash_counted}
                      inputmode="decimal"
                      placeholder="0.00"
                      class="staff-shift-close-input"
                      aria-describedby="staff-shift-close-petty-counted-hint"
                    />
                  </div>
                  <span
                    class="staff-shift-close-section-hint"
                    id="staff-shift-close-petty-counted-hint"
                  >
                    Expected {Menu.format_price(@petty_cash_expected)}. {@petty_cash_transfer_preview}
                  </span>
                </label>

                <label class="staff-shift-close-field">
                  <span>Petty-cash difference reason</span>
                  <textarea
                    name="close[petty_cash_notes]"
                    rows="2"
                    maxlength="500"
                    placeholder="Required only if counted petty cash differs from expected"
                    class="staff-shift-close-input staff-shift-close-input--notes"
                  >{@petty_cash_notes}</textarea>
                </label>

                <label class="staff-shift-close-field" id="staff-shift-close-counted-field">
                  <span>Counted drawer cash</span>
                  <div class="staff-shift-close-input-wrap">
                    <span class="staff-shift-close-currency" aria-hidden="true">₱</span>
                    <input
                      type="text"
                      name="close[counted_cash]"
                      value={@counted_cash}
                      inputmode="decimal"
                      placeholder="0.00"
                      class="staff-shift-close-input"
                      aria-describedby="staff-shift-close-counted-hint"
                    />
                  </div>
                  <span class="staff-shift-close-section-hint" id="staff-shift-close-counted-hint">
                    Required — count after completing the petty-cash transfer above.
                  </span>
                </label>

                <label class="staff-shift-close-field">
                  <span>Notes</span>
                  <textarea
                    name="close[notes]"
                    rows="2"
                    maxlength="500"
                    placeholder="Optional"
                    class="staff-shift-close-input staff-shift-close-input--notes"
                  >{@notes}</textarea>
                </label>

                <p :if={@form_error} class="staff-shift-close-error" id="staff-shift-close-error">
                  {@form_error}
                </p>

                <button
                  :if={!@confirming?}
                  type="submit"
                  class="staff-shift-close-submit"
                  id="staff-shift-close-prepare"
                >
                  Record close
                </button>
              </div>

              <section
                class="staff-shift-close-panel staff-shift-close-panel--secondary"
                aria-label="Payment methods"
              >
                <p class="staff-shift-close-section-label">Payment methods</p>
                <ul class="staff-paid-breakdown" id="staff-shift-close-breakdown">
                  <li :for={row <- @via_rows} class="staff-paid-breakdown-row">
                    <span class="staff-paid-breakdown-label">{row.label}</span>
                    <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                    <span class="staff-paid-breakdown-count">{row.count}</span>
                  </li>
                </ul>
              </section>

              <%= if !Enum.empty?(@staff_shift_summaries) do %>
                <section
                  class="staff-shift-close-panel staff-shift-close-panel--secondary"
                  aria-label="Staff shift sales"
                >
                  <p class="staff-shift-close-section-label">Staff shift sales</p>
                  <ul class="staff-shift-sales-breakdown">
                    <li :for={shift <- @staff_shift_summaries} class="staff-shift-sales-row">
                      <div class="staff-shift-sales-info">
                        <span class="staff-shift-sales-name">{shift.staff_name}</span>
                        <span class="staff-shift-sales-time">
                          {format_shift_time(shift.started_at)} - {format_shift_time(shift.ended_at)}
                        </span>
                      </div>
                      <div class="staff-shift-sales-totals">
                        <span class="staff-shift-sales-total">{Menu.format_price(shift.total)}</span>
                        <span class="staff-shift-sales-count">({shift.order_count} orders)</span>
                      </div>
                    </li>
                  </ul>
                </section>
              <% end %>

              <div
                class="staff-shift-close-system"
                id="staff-shift-close-system"
                aria-label="System paid"
              >
                <p class="staff-shift-close-section-label">System paid</p>
                <p class="staff-shift-close-system-value">
                  {Menu.format_price(@breakdown.total)}
                  <span>({@breakdown.count} orders)</span>
                </p>
                <p class="staff-shift-close-section-hint">Total settled sales recorded today.</p>
              </div>
            </form>
          </div>
        <% end %>

        <section
          class="staff-shift-close-history"
          id="staff-shift-close-history"
          aria-label="Close history"
        >
          <div class="staff-shift-close-history-head">
            <p class="staff-shift-close-section-label">Close history</p>
            <p class="staff-shift-close-section-hint">
              Sealed shop-day snapshots, newest first.
            </p>
          </div>

          <div
            :if={@close_history == []}
            class="staff-shift-close-history-empty"
            id="staff-shift-close-history-empty"
          >
            <strong>No previous closes yet.</strong>
            <p class="staff-shift-close-section-hint">
              Past Close Shop seals will appear here.
            </p>
          </div>

          <div
            :if={@close_history != []}
            class="staff-shift-close-history-list"
            id="staff-shift-close-history-list"
          >
            <article
              :for={entry <- @close_history}
              class={[
                "staff-shift-close-history-row",
                history_open?(@history_open, entry.close.shop_date) && "is-open"
              ]}
              id={"staff-shift-close-history-#{Date.to_iso8601(entry.close.shop_date)}"}
            >
              <button
                type="button"
                class="staff-shift-close-history-summary"
                id={"staff-shift-close-history-toggle-#{Date.to_iso8601(entry.close.shop_date)}"}
                phx-click="toggle_history"
                phx-value-date={Date.to_iso8601(entry.close.shop_date)}
                aria-expanded={
                  if(history_open?(@history_open, entry.close.shop_date),
                    do: "true",
                    else: "false"
                  )
                }
              >
                <span class="staff-shift-close-history-date">
                  {Calendar.strftime(entry.close.shop_date, "%b %-d, %Y")}
                </span>
                <span class="staff-shift-close-history-meta">
                  Closed {Shifts.format_closed_at(entry.close.closed_at)}
                  <span :if={entry.close.closed_by_user}>
                    · {entry.close.closed_by_user.name}
                  </span>
                </span>
                <span class="staff-shift-close-history-totals">
                  {Menu.format_price(entry.close.system_total)}
                  <span>· {entry.close.system_count} orders</span>
                </span>
                <span :if={entry.close.counted_cash} class="staff-shift-close-history-drawer">
                  Drawer {Menu.format_price(entry.close.counted_cash)}
                </span>
              </button>

              <div
                :if={history_open?(@history_open, entry.close.shop_date)}
                class="staff-shift-close-history-detail"
                id={"staff-shift-close-history-detail-#{Date.to_iso8601(entry.close.shop_date)}"}
              >
                <ul class="staff-paid-breakdown staff-shift-close-history-breakdown">
                  <li :for={row <- entry.via_rows} class="staff-paid-breakdown-row">
                    <span class="staff-paid-breakdown-label">{row.label}</span>
                    <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
                    <span class="staff-paid-breakdown-count">{row.count}</span>
                  </li>
                </ul>

                <p :if={entry.close.counted_cash} class="staff-shift-close-history-counted">
                  Counted {Menu.format_price(entry.close.counted_cash)}
                  <span :if={entry.close.variance}>
                    · {variance_copy(entry.close.variance)}
                  </span>
                </p>
                <button
                  :if={Printer.enabled?()}
                  type="button"
                  class="staff-shift-close-history-print"
                  id={"staff-shift-close-print-#{Date.to_iso8601(entry.close.shop_date)}"}
                  phx-click="print_day_report"
                  phx-value-date={Date.to_iso8601(entry.close.shop_date)}
                >
                  Print
                </button>
                <p :if={entry.close.notes} class="staff-shift-close-history-notes">
                  {entry.close.notes}
                </p>
              </div>
            </article>
          </div>

          <button
            :if={@close_history_has_next?}
            type="button"
            id="staff-shift-close-history-more"
            class="staff-shift-close-history-more"
            phx-click="load_more_close_history"
          >
            Load more
          </button>
        </section>

        <.modal
          :if={@confirming?}
          id="staff-shift-close-confirm"
          show
          click_away={false}
          autofocus={false}
          on_cancel={JS.push("cancel_confirm")}
        >
          <div class="staff-confirm-dialog">
            <p class="staff-confirm-dialog-title">🔐 Close Shop?</p>
            <p class="staff-confirm-dialog-copy">
              This will seal today's sales and cash counts.
            </p>

            <div class="staff-confirm-dialog-sections">
              <div class="staff-confirm-section">
                <div class="staff-confirm-section-label">Drawer Cash</div>
                <div class="staff-confirm-section-values">
                  <span class="staff-confirm-value-label">Counted:</span>
                  <span class="staff-confirm-value-amount">₱{@counted_cash}</span>
                </div>
                <div class="staff-confirm-section-values">
                  <span class="staff-confirm-value-label">Expected:</span>
                  <span class="staff-confirm-value-amount">{Menu.format_price(@expected_cash)}</span>
                </div>
                <div class="staff-confirm-section-values" id="staff-shift-close-confirm-cash">
                  <span class="staff-confirm-variance">{variance_copy(@live_variance)}</span>
                </div>
              </div>

              <div class="staff-confirm-section">
                <div class="staff-confirm-section-label">Petty Cash</div>
                <div class="staff-confirm-section-values">
                  <span class="staff-confirm-value-label">Counted:</span>
                  <span class="staff-confirm-value-amount">₱{@petty_cash_counted}</span>
                </div>
                <div class="staff-confirm-section-values">
                  <span class="staff-confirm-value-label">Expected:</span>
                  <span class="staff-confirm-value-amount">
                    {Menu.format_price(@petty_cash_expected)}
                  </span>
                </div>
                <div class="staff-confirm-section-values" id="staff-shift-close-confirm-petty-cash">
                  <span class="staff-confirm-status">{@petty_cash_transfer_preview}</span>
                </div>
              </div>
            </div>

            <p :if={barista?(@current_user)} class="staff-confirm-dialog-note">
              ⏱️ Your staff shift will also end (Time Out).
            </p>

            <div class="staff-confirm-dialog-actions">
              <button
                type="button"
                class="staff-shift-close-submit"
                id="staff-shift-close-submit"
                phx-click="record_close"
                phx-disable-with="Recording…"
              >
                Confirm Seal
              </button>
              <button
                type="button"
                class="staff-shell-tool staff-shell-tool--quiet"
                id="staff-shift-close-cancel-confirm"
                phx-click="cancel_confirm"
              >
                Cancel
              </button>
            </div>
          </div>
        </.modal>
      </main>
    </.staff_shell>
    """
  end

  defp assign_close_state(socket) do
    user = socket.assigns.current_user
    breakdown = Orders.todays_paid_breakdown()
    close = Shifts.get_todays_close()
    already_closed? = not is_nil(close)
    shop_date = if close, do: close.shop_date, else: breakdown.shop_date
    cash_outs = CashOuts.list_recorded_for_shop_date(shop_date)
    cash_out_total = CashOuts.total_for_shop_date(shop_date)

    petty_cash_entries =
      PettyCash.list_for_shop_date(shop_date)
      |> Enum.filter(&(&1.status == "recorded"))

    petty_cash_total = PettyCash.total_for_shop_date(shop_date)
    petty_cash_expected = Decimal.sub(PettyCash.float(), petty_cash_total) |> Decimal.round(2)

    # Get per-staff shift sales summary
    staff_shifts = StaffShifts.list_shifts_for_shop_day(shop_date)

    staff_shift_summaries =
      staff_shifts
      |> Enum.map(fn shift ->
        sales = Orders.sales_summary_for_staff_shift(shift)
        staff_member = Repo.get(User, shift.user_id)

        %{
          id: shift.id,
          user_id: shift.user_id,
          staff_name: (staff_member && staff_member.name) || "Unknown",
          started_at: shift.started_at,
          ended_at: shift.ended_at,
          order_count: sales.order_count,
          total: sales.total
        }
      end)
      |> Enum.sort_by(& &1.started_at)

    {blocked?, block_reason, other_names, staff_shift_ended?} =
      cond do
        already_closed? ->
          ended? =
            barista?(user) and
              match?(%{end_reason: "shift_close"}, latest_closed_shift(user))

          {false, nil, [], ended?}

        true ->
          case Shifts.close_eligibility(user) do
            :ok ->
              {false, nil, [], false}

            {:error, :other_staff_active} ->
              {true, :other_staff_active, other_active_names(user), false}

            {:error, :not_on_shift} ->
              {true, :not_on_shift, [], false}

            {:error, :unauthorized} ->
              {true, :unauthorized, [], false}
          end
      end

    shop_open = Shifts.get_open_for_date(shop_date)
    opening_cash_amount = shop_open && shop_open.opening_cash
    cash_sales = Shifts.cash_sales_total(breakdown)

    expected_cash =
      Shifts.expected_drawer_cash(
        opening_cash_amount,
        cash_sales,
        cash_out_total,
        petty_cash_total
      )

    socket
    |> assign(:page_title, "Close Shop")
    |> assign(:breakdown, breakdown)
    |> assign(:via_rows, Orders.paid_via_rows(breakdown))
    |> assign(:close, close)
    |> assign(:already_closed?, already_closed?)
    |> assign(:blocked?, blocked?)
    |> assign(:block_reason, block_reason)
    |> assign(:other_active_names, other_names)
    |> assign(:staff_shift_ended?, staff_shift_ended?)
    |> assign(:cash_outs, cash_outs)
    |> assign(:cash_out_total, cash_out_total)
    |> assign(:staff_shift_summaries, staff_shift_summaries)
    |> assign(:petty_cash_entries, petty_cash_entries)
    |> assign(:petty_cash_total, petty_cash_total)
    |> assign(:petty_cash_expected, petty_cash_expected)
    |> assign(:shop_open, shop_open)
    |> assign(:opening_cash_amount, opening_cash_amount)
    |> assign(:expected_cash, expected_cash)
    |> assign(:missing_opening?, is_nil(shop_open))
    |> assign(:printer_note, nil)
    |> assign(:counted_cash, "")
    |> assign(:petty_cash_counted, "")
    |> assign(:notes, "")
    |> assign(:petty_cash_notes, "")
    |> assign(:confirming?, false)
    |> assign(:form_error, nil)
    |> reset_close_history()
  end

  defp reset_close_history(socket) do
    %{closes: closes, has_next_page: has_next?, next_cursor: next_cursor} =
      Shifts.list_close_history()

    socket
    |> assign(:close_history, Enum.map(closes, &history_entry/1))
    |> assign(:close_history_has_next?, has_next?)
    |> assign(:close_history_next_cursor, next_cursor)
    |> assign_new(:history_open, fn -> nil end)
  end

  defp append_close_history(socket) do
    cursor = socket.assigns.close_history_next_cursor

    if socket.assigns.close_history_has_next? and not is_nil(cursor) do
      %{closes: closes, has_next_page: has_next?, next_cursor: next_cursor} =
        Shifts.list_close_history(cursor: cursor)

      socket
      |> assign(
        :close_history,
        socket.assigns.close_history ++ Enum.map(closes, &history_entry/1)
      )
      |> assign(:close_history_has_next?, has_next?)
      |> assign(:close_history_next_cursor, next_cursor)
    else
      socket
    end
  end

  defp history_entry(close) do
    %{close: close, via_rows: closed_via_rows(close)}
  end

  defp history_open?(open, %Date{} = date) do
    open == Date.to_iso8601(date)
  end

  defp history_open?(_, _), do: false

  defp latest_closed_shift(%User{id: user_id}) do
    case StaffShifts.list_shifts_for_user(user_id, limit: 1) do
      [shift | _] -> shift
      _ -> nil
    end
  end

  defp other_active_names(%User{id: user_id}) do
    StaffShifts.list_open_shifts()
    |> Enum.reject(&(&1.user_id == user_id))
    |> Enum.map(fn shift ->
      case shift.user do
        %{name: name} when is_binary(name) and name != "" -> name
        _ -> "Staff ##{shift.user_id}"
      end
    end)
  end

  defp other_staff_message,
    do:
      "Another staff member is still on shift. They need to Time Out before you can Close Shop."

  defp close_success_flash(true), do: "Shift close recorded. Your staff shift has ended."
  defp close_success_flash(false), do: "Shift close recorded"

  defp barista?(%User{role: "barista"}), do: true
  defp barista?(_), do: false

  defp close_changeset_error(_changeset),
    do: "Could not record shift close. Check the amounts and try again."

  defp close_shop_date(%{already_closed?: true, close: %{shop_date: shop_date}})
       when not is_nil(shop_date),
       do: shop_date

  defp close_shop_date(%{breakdown: %{shop_date: shop_date}}), do: shop_date
  defp close_shop_date(_), do: Orders.shop_date_today()

  defp open_cash_total(%{via_rows: rows}) when is_list(rows) do
    case Enum.find(rows, &(&1.via == "cash")) do
      %{total: total} -> total
      _ -> Decimal.new("0")
    end
  end

  defp open_cash_total(_), do: Decimal.new("0")

  defp closed_via_rows(nil), do: []

  defp closed_via_rows(%{by_via: by_via}) when is_map(by_via) do
    Enum.map(~w(cash gcash maya counter paymongo), fn via ->
      entry = Map.get(by_via, via, %{})

      %{
        via: via,
        label: Orders.paid_via_label(via),
        total: snapshot_entry_total(entry),
        count: snapshot_entry_count(entry)
      }
    end)
  end

  defp closed_via_rows(_), do: []

  defp snapshot_cash_total(nil), do: Decimal.new("0")

  defp snapshot_cash_total(%{by_via: by_via}) when is_map(by_via) do
    by_via
    |> Map.get("cash", %{})
    |> snapshot_entry_total()
  end

  defp snapshot_cash_total(_), do: Decimal.new("0")

  defp snapshot_entry_total(entry) when is_map(entry) do
    raw = Map.get(entry, "total") || Map.get(entry, :total) || "0"

    case Decimal.parse(to_string(raw)) do
      {decimal, _} -> decimal
      :error -> Decimal.new("0")
    end
  end

  defp snapshot_entry_total(_), do: Decimal.new("0")

  defp snapshot_entry_count(entry) when is_map(entry) do
    Map.get(entry, "count") || Map.get(entry, :count) || 0
  end

  defp snapshot_entry_count(_), do: 0

  defp printable_close(socket, params) do
    case Map.get(params, "date") do
      date when is_binary(date) and date != "" ->
        case Date.from_iso8601(date) do
          {:ok, shop_date} -> Shifts.get_close_for_date(shop_date)
          _ -> nil
        end

      _ ->
        socket.assigns[:close]
    end
  end

  defp live_variance(counted_cash, expected_cash) do
    counted = counted_cash |> to_string() |> String.trim()

    if counted == "" do
      nil
    else
      Shifts.drawer_variance(counted, expected_cash)
    end
  end

  defp petty_cash_variance(counted_value, expected_cash) do
    case parse_display_decimal(counted_value) do
      %Decimal{} = counted -> Shifts.drawer_variance(counted, expected_cash)
      _ -> nil
    end
  end

  defp petty_cash_transfer(counted_value, total_expenses) do
    case parse_display_decimal(counted_value) do
      %Decimal{} = counted ->
        Decimal.sub(PettyCash.float(), counted) |> Decimal.round(2)

      _ ->
        Decimal.round(total_expenses || Decimal.new("0"), 2)
    end
  end

  defp petty_cash_transfer_preview(counted_value) do
    case parse_display_decimal(counted_value) do
      %Decimal{} = counted ->
        transfer = Decimal.sub(PettyCash.float(), counted) |> Decimal.round(2)

        case Decimal.compare(transfer, 0) do
          :gt -> "Move #{Menu.format_price(transfer)} from drawer to petty cash."
          :lt -> "Return #{Menu.format_price(Decimal.abs(transfer))} from petty cash to drawer."
          :eq -> "No drawer transfer needed."
        end

      _ ->
        "The system calculates the transfer after you enter the count."
    end
  end

  defp parse_display_decimal(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} ->
        if Decimal.compare(decimal, 0) == :lt, do: nil, else: Decimal.round(decimal, 2)

      _ ->
        nil
    end
  end

  defp parse_display_decimal(%Decimal{} = decimal) do
    if Decimal.compare(decimal, 0) == :lt, do: nil, else: Decimal.round(decimal, 2)
  end

  defp parse_display_decimal(_), do: nil

  defp variance_copy(nil), do: "Enter counted cash to see over/short."

  defp variance_copy(%Decimal{} = variance) do
    abs = Decimal.abs(variance)

    case Decimal.compare(variance, 0) do
      :eq -> "Even with expected"
      :gt -> "Over #{Menu.format_price(abs)}"
      :lt -> "Short #{Menu.format_price(abs)}"
    end
  end

  defp variance_copy(_), do: "Enter counted cash to see over/short."

  defp drawer_money(nil), do: "—"
  defp drawer_money(amount), do: Menu.format_price(amount)

  defp format_shift_time(%DateTime{} = dt) do
    manila = DateTime.add(dt, 8 * 60 * 60, :second)
    Calendar.strftime(manila, "%I:%M %p") |> String.trim_leading("0")
  end

  defp format_shift_time(nil), do: "—"
end
