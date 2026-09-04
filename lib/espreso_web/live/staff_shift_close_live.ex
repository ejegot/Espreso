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
     |> assign(:form_error, nil)}
  end

  def handle_event("record_close", %{"close" => params}, socket) do
    case Shifts.record_close(socket.assigns.current_user, params) do
      {:ok, close} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shift close recorded")
         |> assign(:close, close)
         |> assign(:already_closed?, true)
         |> assign(:form_error, nil)}

      {:error, :already_closed} ->
        {:noreply,
         socket
         |> assign(:close, Shifts.get_todays_close())
         |> assign(:already_closed?, true)
         |> assign(:form_error, "Shift already closed for today.")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don’t have access to close shift.")
         |> push_navigate(to: ~p"/staff")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form_error, close_changeset_error(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:home} current_user={@current_user} page_title="Close shift">
      <main class="staff-home-main staff-shift-close" id="staff-shift-close">
        <header class="staff-shift-close-head">
          <p class="staff-home-desk-eyebrow">End of day</p>
          <h2 class="staff-home-desk-title">
            Close shift · {Calendar.strftime(@breakdown.shop_date, "%b %d")}
          </h2>
          <p class="staff-home-lede">
            System totals are read-only. Count cash in the drawer, then record the close.
          </p>
        </header>

        <section class="staff-shift-close-totals" aria-label="System totals">
          <div class="staff-shift-close-total-row">
            <p class="staff-shift-close-total-label">System paid</p>
            <p class="staff-shift-close-total-value">
              {Menu.format_price(@breakdown.total)}
              <span>({@breakdown.count} orders)</span>
            </p>
          </div>

          <ul class="staff-paid-breakdown" id="staff-shift-close-breakdown">
            <li :for={row <- @via_rows} class="staff-paid-breakdown-row">
              <span class="staff-paid-breakdown-label">{row.label}</span>
              <span class="staff-paid-breakdown-total">{Menu.format_price(row.total)}</span>
              <span class="staff-paid-breakdown-count">{row.count}</span>
            </li>
          </ul>
        </section>

        <%= if @already_closed? and @close do %>
          <section class="staff-shift-close-done" id="staff-shift-close-done" role="status">
            <p class="staff-shift-close-done-badge">Closed</p>
            <p class="staff-shift-close-done-copy">
              {Shifts.format_closed_at(@close.closed_at)}
              <span :if={@close.closed_by_user}> by {@close.closed_by_user.name}</span>
            </p>
            <p :if={@close.counted_cash} class="staff-shift-close-done-cash">
              Counted cash · {Menu.format_price(@close.counted_cash)}
            </p>
            <p :if={@close.notes} class="staff-shift-close-done-notes">{@close.notes}</p>
            <.link navigate={~p"/staff"} class="staff-shell-tool">Back to Home</.link>
          </section>
        <% else %>
          <form
            id="staff-shift-close-form"
            phx-change="validate"
            phx-submit="record_close"
            class="staff-shift-close-form"
          >
            <label class="staff-shift-close-field">
              <span>Counted cash in drawer</span>
              <input
                type="text"
                name="close[counted_cash]"
                value={@counted_cash}
                inputmode="decimal"
                placeholder="Optional"
                class="staff-shift-close-input"
              />
            </label>

            <label class="staff-shift-close-field">
              <span>Notes</span>
              <textarea
                name="close[notes]"
                rows="3"
                maxlength="500"
                placeholder="Optional"
                class="staff-shift-close-input staff-shift-close-input--notes"
              >{@notes}</textarea>
            </label>

            <p :if={@form_error} class="staff-shift-close-error" id="staff-shift-close-error">
              {@form_error}
            </p>

            <button type="submit" class="staff-shift-close-submit" id="staff-shift-close-submit">
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
    |> assign(:form_error, nil)
  end

  defp close_changeset_error(_changeset), do: "Could not record shift close. Check the amounts and try again."
end
