defmodule EspresoWeb.StaffAttendanceLive do
  @moduledoc """
  Manager/Owner shop-day view of all staff attendance and paid POS sales.
  """
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Authorization.can?(user, :reports) do
      today = Orders.shop_date_today()

      {:ok,
       socket
       |> assign(:page_title, "Staff attendance")
       |> assign(:selected_date, today)
       |> load_attendance(), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to staff attendance.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("select_date", %{"shop_date" => raw}, socket) do
    {:noreply, apply_selected_date(socket, parse_shop_date(raw))}
  end

  def handle_event("select_today", _params, socket) do
    {:noreply, apply_selected_date(socket, Orders.shop_date_today())}
  end

  def handle_event("previous_day", _params, socket) do
    {:noreply, apply_selected_date(socket, Date.add(socket.assigns.selected_date, -1))}
  end

  def handle_event("next_day", _params, socket) do
    today = Orders.shop_date_today()
    next = Date.add(socket.assigns.selected_date, 1)

    date = if Date.compare(next, today) == :gt, do: today, else: next
    {:noreply, apply_selected_date(socket, date)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:attendance} current_user={@current_user} page_title="Staff attendance">
      <main class="staff-attendance" id="staff-attendance">
        <header class="staff-attendance-head">
          <div>
            <p class="staff-attendance-eyebrow" id="staff-attendance-eyebrow">
              <%= if @today? do %>
                Today · {@shop_date_label}
              <% else %>
                {@shop_date_label}
              <% end %>
            </p>
            <h2>Staff attendance</h2>
            <p>
              <%= if @today? do %>
                Who’s working and their paid POS sales today
              <% else %>
                Staff shifts and paid POS sales for this shop day
              <% end %>
            </p>
          </div>

          <form
            class="staff-attendance-date-nav"
            id="staff-attendance-date-nav"
            phx-change="select_date"
          >
            <button
              type="button"
              id="staff-attendance-prev"
              class="staff-attendance-date-btn"
              phx-click="previous_day"
            >
              ‹ Prev
            </button>

            <label class="staff-attendance-date-field">
              <span>Shop date</span>
              <input
                type="date"
                name="shop_date"
                id="staff-attendance-date"
                value={Date.to_iso8601(@selected_date)}
                max={Date.to_iso8601(@today_date)}
              />
            </label>

            <button
              type="button"
              id="staff-attendance-next"
              class="staff-attendance-date-btn"
              phx-click="next_day"
              disabled={@today?}
            >
              Next ›
            </button>

            <button
              :if={!@today?}
              type="button"
              id="staff-attendance-today"
              class="staff-attendance-date-btn staff-attendance-date-btn--today"
              phx-click="select_today"
            >
              Today
            </button>
          </form>
        </header>

        <section
          :if={@working != []}
          class="staff-attendance-section"
          id="staff-attendance-working"
          aria-label={if(@today?, do: "Currently working", else: "Open shifts")}
        >
          <p class="staff-attendance-section-label">
            {if @today?, do: "Currently working", else: "Open shifts"}
          </p>
          <div class="staff-attendance-list">
            <article
              :for={entry <- @working}
              class="staff-attendance-row staff-attendance-row--open"
              id={"attendance-shift-#{entry.shift.id}"}
            >
              <p class="staff-attendance-name">{employee_name(entry.shift)}</p>
              <p class="staff-attendance-when">
                {format_shop_time(entry.shift.started_at)}
                <span aria-hidden="true">·</span>
                <span class="staff-badge">OPEN</span>
              </p>
              <p class="staff-attendance-sales">
                {format_orders(entry.sales.order_count)} · {Menu.format_price(entry.sales.total)}
              </p>
            </article>
          </div>
        </section>

        <section
          :if={@completed != []}
          class="staff-attendance-section"
          id="staff-attendance-completed"
          aria-label={if(@today?, do: "Completed today", else: "Completed")}
        >
          <p class="staff-attendance-section-label">
            {if @today?, do: "Completed today", else: "Completed"}
          </p>
          <div class="staff-attendance-list">
            <article
              :for={entry <- @completed}
              class="staff-attendance-row"
              id={"attendance-shift-#{entry.shift.id}"}
            >
              <p class="staff-attendance-name">{employee_name(entry.shift)}</p>
              <p class="staff-attendance-when">
                {format_shop_time(entry.shift.started_at)} – {format_shop_time(entry.shift.ended_at)}
              </p>
              <p class="staff-attendance-sales">
                {format_orders(entry.sales.order_count)} · {Menu.format_price(entry.sales.total)}
              </p>
            </article>
          </div>
        </section>

        <div
          :if={@working == [] and @completed == []}
          class="staff-attendance-empty"
          id="staff-attendance-empty"
        >
          <strong>
            {if @today?, do: "No staff shifts today.", else: "No attendance records for this day."}
          </strong>
        </div>
      </main>
    </.staff_shell>
    """
  end

  defp apply_selected_date(socket, nil), do: socket

  defp apply_selected_date(socket, %Date{} = date) do
    today = Orders.shop_date_today()
    date = if Date.compare(date, today) == :gt, do: today, else: date

    socket
    |> assign(:selected_date, date)
    |> load_attendance()
  end

  defp load_attendance(socket) do
    today = Orders.shop_date_today()
    shop_date = Map.get(socket.assigns, :selected_date) || today
    today? = Date.compare(shop_date, today) == :eq

    shifts = StaffShifts.list_shifts_for_shop_day(shop_date)
    entries = Enum.map(shifts, &with_sales/1)
    {working, completed} = Enum.split_with(entries, &is_nil(&1.shift.ended_at))

    socket
    |> assign(:selected_date, shop_date)
    |> assign(:today_date, today)
    |> assign(:today?, today?)
    |> assign(:shop_date, shop_date)
    |> assign(:shop_date_label, Calendar.strftime(shop_date, "%b %-d, %Y"))
    |> assign(:working, working)
    |> assign(:completed, completed)
  end

  defp parse_shop_date(raw) when is_binary(raw) do
    case Date.from_iso8601(String.trim(raw)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_shop_date(_), do: nil

  defp with_sales(%StaffShift{} = shift) do
    %{shift: shift, sales: Orders.sales_summary_for_staff_shift(shift)}
  end

  defp employee_name(%StaffShift{user: %{name: name}}) when is_binary(name), do: name
  defp employee_name(_), do: "Staff"

  defp format_orders(1), do: "1 order"
  defp format_orders(count) when is_integer(count), do: "#{count} orders"

  defp format_shop_time(%DateTime{} = at),
    do: at |> manila_time() |> Calendar.strftime("%-I:%M %p")

  defp format_shop_time(_), do: "—"

  defp manila_time(at), do: DateTime.add(at, 8 * 60 * 60, :second)
end
