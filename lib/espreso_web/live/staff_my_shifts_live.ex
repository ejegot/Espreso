defmodule EspresoWeb.StaffMyShiftsLive do
  @moduledoc """
  Personal staff attendance and POS sales history for the authenticated employee.
  """
  use EspresoWeb, :live_view

  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  @history_limit 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "My shifts")
     |> load_my_shifts(), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:my_shifts} current_user={@current_user} page_title="My shifts">
      <main class="staff-my-shifts" id="staff-my-shifts">
        <header class="staff-my-shifts-head">
          <div>
            <p class="staff-my-shifts-eyebrow">Attendance</p>
            <h2>My shifts</h2>
            <p>Your Time In, Time Out, and paid POS sales.</p>
          </div>
        </header>

        <section
          :if={@current_shift}
          class="staff-my-shifts-current"
          id="my-shifts-current"
          aria-label="Current shift"
        >
          <p class="staff-my-shifts-section-label">Current shift</p>
          <div class="staff-my-shift-card staff-my-shift-card--open">
            <div class="staff-my-shift-card-main">
              <p class="staff-my-shift-when">
                {format_shift_date(@current_shift.shift.started_at)} · {format_shop_time(
                  @current_shift.shift.started_at
                )}
                <span aria-hidden="true">·</span>
                <span class="staff-badge staff-my-shift-open-badge">OPEN</span>
              </p>
              <p class="staff-my-shift-sales">
                {format_orders(@current_shift.sales.order_count)} · {Menu.format_price(
                  @current_shift.sales.total
                )}
              </p>
            </div>
          </div>
        </section>

        <section class="staff-my-shifts-history" aria-label="Recent shifts">
          <p :if={@history_shifts != []} class="staff-my-shifts-section-label">Recent shifts</p>

          <div :if={@history_shifts != []} class="staff-my-shifts-list" id="my-shifts-history">
            <article
              :for={entry <- @history_shifts}
              class="staff-my-shift-row"
              id={"my-shift-#{entry.shift.id}"}
            >
              <div class="staff-my-shift-row-main">
                <p class="staff-my-shift-when">
                  {format_shift_range(entry.shift)}
                </p>
                <p class="staff-my-shift-sales">
                  {format_orders(entry.sales.order_count)} · {Menu.format_price(entry.sales.total)}
                </p>
              </div>
            </article>
          </div>

          <div
            :if={is_nil(@current_shift) and @history_shifts == []}
            class="staff-my-shifts-empty"
            id="my-shifts-empty"
          >
            <strong>No shift history yet.</strong>
            <p class="staff-my-shifts-empty-hint">
              Your shifts appear here after you sign in and work a session.
            </p>
          </div>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp load_my_shifts(socket) do
    user = socket.assigns.current_user
    shifts = StaffShifts.list_shifts_for_user(user.id, limit: @history_limit)

    current =
      case Enum.find(shifts, &is_nil(&1.ended_at)) do
        %StaffShift{} = open -> with_sales(open)
        nil -> nil
      end

    history =
      shifts
      |> Enum.reject(&is_nil(&1.ended_at))
      |> Enum.map(&with_sales/1)

    socket
    |> assign(:current_shift, current)
    |> assign(:history_shifts, history)
  end

  defp with_sales(%StaffShift{} = shift) do
    %{shift: shift, sales: Orders.sales_summary_for_staff_shift(shift)}
  end

  defp format_orders(1), do: "1 order"
  defp format_orders(count) when is_integer(count), do: "#{count} orders"

  defp format_shift_range(%StaffShift{started_at: started_at, ended_at: ended_at}) do
    date = format_shift_date(started_at)
    "#{date} · #{format_shop_time(started_at)} – #{format_shop_time(ended_at)}"
  end

  defp format_shift_date(%DateTime{} = at) do
    at |> manila_time() |> Calendar.strftime("%b %-d")
  end

  defp format_shop_time(%DateTime{} = at),
    do: at |> manila_time() |> Calendar.strftime("%-I:%M %p")

  defp format_shop_time(_), do: "—"

  defp manila_time(at), do: DateTime.add(at, 8 * 60 * 60, :second)
end
