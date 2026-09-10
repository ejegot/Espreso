defmodule EspresoWeb.StaffShiftCloseLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.CashOuts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Shifts
  alias Espreso.StaffShifts

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
       |> assign(:notes, Map.get(params, "notes", ""))
       |> assign(:confirming?, false)
       |> assign(:form_error, nil)}
    end
  end

  def handle_event("prepare_close", %{"close" => params}, socket) do
    if socket.assigns.blocked? do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:counted_cash, Map.get(params, "counted_cash", ""))
       |> assign(:notes, Map.get(params, "notes", ""))
       |> assign(:confirming?, true)
       |> assign(:form_error, nil)}
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
        "notes" => socket.assigns.notes
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
           |> assign(:form_error, nil)}

        {:error, :already_closed} ->
          {:noreply,
           socket
           |> assign(:close, Shifts.get_todays_close())
           |> assign(:already_closed?, true)
           |> assign(:blocked?, false)
           |> assign(:confirming?, false)
           |> assign(:form_error, "Shift already closed for today.")}

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

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:confirming?, false)
           |> assign(:form_error, close_changeset_error(changeset))}
      end
    end
  end

  @impl true
  def render(assigns) do
    shop_date = close_shop_date(assigns)
    cash_total = open_cash_total(assigns)
    snapshot_rows = closed_via_rows(assigns[:close])
    snapshot_cash = snapshot_cash_total(assigns[:close])

    assigns =
      assigns
      |> assign(:shop_date, shop_date)
      |> assign(:cash_total, cash_total)
      |> assign(:snapshot_rows, snapshot_rows)
      |> assign(:snapshot_cash, snapshot_cash)

    ~H"""
    <.staff_shell current={:close} current_user={@current_user} page_title="Close shift">
      <main class="staff-home-main staff-shift-close" id="staff-shift-close">
        <header class="staff-shift-close-head">
          <p class="staff-home-desk-eyebrow">End of day</p>
          <div class="staff-shift-close-title-row">
            <h2 class="staff-home-desk-title">
              Close shift · {Calendar.strftime(@shop_date, "%b %d")}
            </h2>
            <p
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
            </p>
          </div>
          <p class="staff-home-lede staff-shift-close-lede">
            <%= cond do %>
              <% @already_closed? -> %>
                Sealed snapshot of today’s settled sales and the drawer cash count that was recorded.
              <% @block_reason == :other_staff_active -> %>
                Another staff member is still on shift. They need to Time Out before you can Close Shift.
              <% @block_reason == :not_on_shift -> %>
                You need an open staff shift to close the shop. Log in again if your shift already ended.
              <% true -> %>
                Review today’s settled sales, enter the cash physically counted in the drawer, then seal the day.
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

            <div class="staff-shift-close-counted-display" id="staff-shift-close-sealed-counted">
              <p class="staff-shift-close-section-label">Counted drawer cash</p>
              <%= if @close.counted_cash do %>
                <p class="staff-shift-close-cash-value">{Menu.format_price(@close.counted_cash)}</p>
              <% else %>
                <p class="staff-shift-close-section-hint">No drawer cash count was entered.</p>
              <% end %>
            </div>

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
              <.link
                :if={Authorization.can?(@current_user, :dashboard) and not barista?(@current_user)}
                navigate={~p"/dashboard"}
                class="staff-shell-tool staff-shell-tool--quiet"
              >
                Back to Dashboard
              </.link>
              <.link navigate={~p"/transactions"} class="staff-shell-tool staff-shell-tool--quiet">
                View Transactions
              </.link>
            </div>
          </section>
        <% else %>
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
                Another staff member is still on shift. They need to Time Out before you can Close Shift.
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

          <form
            :if={!@blocked?}
            id="staff-shift-close-form"
            phx-change="validate"
            phx-submit="prepare_close"
            class="staff-shift-close-form"
          >
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
                Optional — enter the cash physically counted at close.
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

            <p :if={@form_error} class="staff-shift-close-error" id="staff-shift-close-error">
              {@form_error}
            </p>

            <div :if={@confirming?} class="staff-shift-close-confirm" id="staff-shift-close-confirm">
              <p class="staff-shift-close-confirm-title">Record today’s close?</p>
              <p class="staff-shift-close-confirm-copy">
                This will seal today’s recorded paid sales and save the cash count you entered.
                <span :if={barista?(@current_user)}>
                  Your staff shift will also end (Time Out).
                </span>
              </p>
              <p class="staff-shift-close-confirm-cash" id="staff-shift-close-confirm-cash">
                <%= if String.trim(@counted_cash || "") == "" do %>
                  No drawer cash count entered.
                <% else %>
                  Counted drawer cash · ₱{@counted_cash}
                <% end %>
              </p>
              <div class="staff-shift-close-confirm-actions">
                <button
                  type="button"
                  class="staff-shift-close-submit"
                  id="staff-shift-close-submit"
                  phx-click="record_close"
                  phx-disable-with="Recording…"
                >
                  Confirm seal
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

            <button
              :if={!@confirming?}
              type="submit"
              class="staff-shift-close-submit"
              id="staff-shift-close-prepare"
            >
              Record close
            </button>
          </form>
        <% end %>
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

    socket
    |> assign(:page_title, "Close shift")
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
    |> assign(:counted_cash, "")
    |> assign(:notes, "")
    |> assign(:confirming?, false)
    |> assign(:form_error, nil)
  end

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
      "Another staff member is still on shift. They need to Time Out before you can Close Shift."

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
end
