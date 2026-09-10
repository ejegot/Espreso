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
      {:ok,
       socket
       |> assign(:page_title, "Staff attendance")
       |> load_attendance(), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to staff attendance.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:attendance} current_user={@current_user} page_title="Staff attendance">
      <main class="staff-attendance" id="staff-attendance">
        <header class="staff-attendance-head">
          <div>
            <p class="staff-attendance-eyebrow">Today · {@shop_date_label}</p>
            <h2>Staff attendance</h2>
            <p>Who’s working and their paid POS sales today</p>
          </div>
        </header>

        <section
          :if={@working != []}
          class="staff-attendance-section"
          id="staff-attendance-working"
          aria-label="Currently working"
        >
          <p class="staff-attendance-section-label">Currently working</p>
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
          aria-label="Completed today"
        >
          <p class="staff-attendance-section-label">Completed today</p>
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
          <strong>No staff shifts today.</strong>
        </div>
      </main>
    </.staff_shell>
    """
  end

  defp load_attendance(socket) do
    shop_date = Orders.shop_date_today()
    shifts = StaffShifts.list_shifts_for_shop_day(shop_date)

    entries = Enum.map(shifts, &with_sales/1)
    {working, completed} = Enum.split_with(entries, &is_nil(&1.shift.ended_at))

    socket
    |> assign(:shop_date, shop_date)
    |> assign(:shop_date_label, Calendar.strftime(shop_date, "%b %-d, %Y"))
    |> assign(:working, working)
    |> assign(:completed, completed)
  end

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
