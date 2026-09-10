defmodule EspresoWeb.StaffShiftCloseLive do
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Shifts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Authorization.can?(user, :reports) do
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
    {:noreply,
     socket
     |> assign(:counted_cash, Map.get(params, "counted_cash", ""))
     |> assign(:notes, Map.get(params, "notes", ""))
     |> assign(:confirming?, false)
     |> assign(:form_error, nil)}
  end

  def handle_event("prepare_close", %{"close" => params}, socket) do
    {:noreply,
     socket
     |> assign(:counted_cash, Map.get(params, "counted_cash", ""))
     |> assign(:notes, Map.get(params, "notes", ""))
     |> assign(:confirming?, true)
     |> assign(:form_error, nil)}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirming?, false)}
  end

  def handle_event("record_close", _params, socket) do
    params = %{
      "counted_cash" => socket.assigns.counted_cash,
      "notes" => socket.assigns.notes
    }

    case Shifts.record_close(socket.assigns.current_user, params) do
      {:ok, close} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shift close recorded")
         |> assign(:close, close)
         |> assign(:already_closed?, true)
         |> assign(:confirming?, false)
         |> assign(:form_error, nil)}

      {:error, :already_closed} ->
        {:noreply,
         socket
         |> assign(:close, Shifts.get_todays_close())
         |> assign(:already_closed?, true)
         |> assign(:confirming?, false)
         |> assign(:form_error, "Shift already closed for today.")}

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
                @already_closed? && "staff-shift-close-status--closed"
              ]}
              id="staff-shift-close-status"
            >
              {if(@already_closed?, do: "Shift closed", else: "Open")}
            </p>
          </div>
          <p class="staff-home-lede staff-shift-close-lede">
            <%= if @already_closed? do %>
              Sealed snapshot of today’s settled sales and the drawer cash count that was recorded.
            <% else %>
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
            <p class="staff-shift-close-seal-note">
              These are the numbers sealed when this shift was closed.
            </p>

            <div class="staff-shift-close-cash" id="staff-shift-close-sealed-cash">
              <p class="staff-shift-close-section-label">Cash settled</p>
              <p class="staff-shift-close-cash-value">{Menu.format_price(@snapshot_cash)}</p>
              <p class="staff-shift-close-section-hint">Cash payments sealed in this close.</p>
            </div>

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
              <.link navigate={~p"/staff"} class="staff-shell-tool">Back to Home</.link>
              <.link navigate={~p"/dashboard"} class="staff-shell-tool staff-shell-tool--quiet">
                Back to Dashboard
              </.link>
              <.link navigate={~p"/transactions"} class="staff-shell-tool staff-shell-tool--quiet">
                View Transactions
              </.link>
            </div>
          </section>
        <% else %>
          <section
            class="staff-shift-close-cash"
            id="staff-shift-close-cash"
            aria-label="Cash settled"
          >
            <p class="staff-shift-close-section-label">Cash settled</p>
            <p class="staff-shift-close-cash-value">{Menu.format_price(@cash_total)}</p>
            <p class="staff-shift-close-section-hint">Cash payments recorded as paid today.</p>
          </section>

          <form
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
    breakdown = Orders.todays_paid_breakdown()
    close = Shifts.get_todays_close()

    socket
    |> assign(:page_title, "Close shift")
    |> assign(:breakdown, breakdown)
    |> assign(:via_rows, Orders.paid_via_rows(breakdown))
    |> assign(:close, close)
    |> assign(:already_closed?, not is_nil(close))
    |> assign(:counted_cash, "")
    |> assign(:notes, "")
    |> assign(:confirming?, false)
    |> assign(:form_error, nil)
  end

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
