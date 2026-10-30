defmodule EspresoWeb.StaffCloseMyShiftLive do
  @moduledoc """
  Close the current staff member's shift (personal time out).

  This is separate from shop-day close. Records the staff shift `ended_at` timestamp.
  """

  use EspresoWeb, :live_view

  alias Espreso.Orders
  alias Espreso.StaffShifts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    case StaffShifts.get_open_shift(user.id) do
      %StaffShifts.StaffShift{} = shift ->
        sales = Orders.sales_summary_for_staff_shift(shift)

        {:ok,
         socket
         |> assign(:page_title, "End My Shift")
         |> assign(:shift, shift)
         |> assign(:sales, sales)
         |> assign(:confirming?, false)
         |> assign(:show_form?, true)
         |> assign(:closed?, false), layout: false}

      nil ->
        {:ok,
         socket
         |> put_flash(:info, "You don't have an open shift.")
         |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("close_shift", _params, socket) do
    user = socket.assigns.current_user
    closed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    case StaffShifts.close_shift_for_shift_close(user.id, closed_at) do
      {:ok, %StaffShifts.StaffShift{} = shift} ->
        sales = Orders.sales_summary_for_staff_shift(shift)

        {:noreply,
         socket
         |> assign(:shift, shift)
         |> assign(:sales, sales)
         |> assign(:closed?, true)
         |> assign(:show_form?, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to close shift: #{inspect(reason)}")}
    end
  end

  def handle_event("confirm_close", _params, socket) do
    {:noreply, assign(socket, :confirming?, true)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:confirming?, false)
     |> push_navigate(to: ~p"/staff")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell
      current={:close_my_shift}
      current_user={@current_user}
      page_title="End My Shift"
      chrome={:bar}
    >
      <main class="staff-close-my-shift-main" id="staff-close-my-shift-desk">
        <%= if @closed? do %>
          <div class="close-my-shift-complete">
            <div class="close-my-shift-complete-header">
              <h1 class="text-2xl font-bold text-slate-900">Shift closed</h1>
              <p class="text-slate-600 mt-2">
                Your shift has been closed at <strong>{format_time(@shift.ended_at)}</strong>
              </p>
            </div>

            <section class="mt-6 bg-white rounded-lg border border-slate-200 p-6">
              <div class="space-y-4">
                <div class="flex justify-between">
                  <span class="text-slate-600">Started at:</span>
                  <strong class="text-slate-900">{format_time(@shift.started_at)}</strong>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-600">Ended at:</span>
                  <strong class="text-slate-900">{format_time(@shift.ended_at)}</strong>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-600">Duration:</span>
                  <strong class="text-slate-900">
                    {format_duration(@shift.started_at, @shift.ended_at)}
                  </strong>
                </div>
                <div class="flex justify-between pt-4 border-t">
                  <span class="text-slate-600">Reason:</span>
                  <strong class="text-slate-900">{@shift.end_reason}</strong>
                </div>
                <div class="flex justify-between pt-3">
                  <span class="text-slate-600">Orders completed:</span>
                  <strong class="text-slate-900">{@sales.order_count}</strong>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-600">Your sales:</span>
                  <strong class="text-lg text-green-700">
                    {Espreso.Menu.format_price(@sales.total)}
                  </strong>
                </div>
              </div>
            </section>

            <div class="mt-6 flex gap-3">
              <.link navigate={~p"/staff"} class="btn btn-primary">
                Back to Home
              </.link>
              <.link navigate={~p"/staff/shifts"} class="btn btn-secondary">
                View My Shifts
              </.link>
            </div>
          </div>
        <% else %>
          <div class="close-my-shift-form">
            <%= if @confirming? do %>
              <div class="confirm-dialog" id="confirm-close-dialog">
                <div class="confirm-dialog-overlay" phx-click="cancel"></div>
                <div class="confirm-dialog-content">
                  <div class="confirm-dialog-header">
                    <h2 class="text-lg font-semibold text-slate-900">Close your shift?</h2>
                  </div>

                  <div class="confirm-dialog-body">
                    <p class="text-slate-600">
                      This will record your shift end time at
                      <strong>{format_time(DateTime.utc_now())}</strong>
                    </p>
                    <p class="text-slate-600 mt-2">
                      You can stay logged in and continue working, <br />
                      but no new orders will be attributed to this shift.
                    </p>
                  </div>

                  <div class="confirm-dialog-actions">
                    <button phx-click="cancel" class="btn btn-secondary">
                      Cancel
                    </button>
                    <button phx-click="close_shift" class="btn btn-primary">
                      Yes, end my shift
                    </button>
                  </div>
                </div>
              </div>
            <% end %>

            <div class="close-my-shift-content">
              <section class="mb-6">
                <h1 class="text-2xl font-bold text-slate-900 mb-2">Close your shift</h1>
                <p class="text-slate-600">
                  End your current shift and lock your time. You can stay logged in if you want.
                </p>
              </section>

              <section class="bg-white rounded-lg border border-slate-200 p-6 mb-6">
                <h2 class="text-lg font-semibold text-slate-900 mb-4">Shift details</h2>
                <div class="space-y-3">
                  <div class="flex justify-between">
                    <span class="text-slate-600">Started at:</span>
                    <strong class="text-slate-900">{format_time(@shift.started_at)}</strong>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-slate-600">Current time:</span>
                    <strong class="text-slate-900">{format_time(DateTime.utc_now())}</strong>
                  </div>
                  <div class="flex justify-between pt-3 border-t">
                    <span class="text-slate-600">Orders completed:</span>
                    <strong class="text-slate-900">{@sales.order_count}</strong>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-slate-600">Your sales today:</span>
                    <strong class="text-lg text-green-700">
                      {Espreso.Menu.format_price(@sales.total)}
                    </strong>
                  </div>
                </div>
              </section>

              <div class="flex gap-3">
                <button
                  phx-click="confirm_close"
                  class="flex-1 btn btn-primary bg-[#3d5a3d] text-white rounded-lg px-4 py-2 font-medium"
                >
                  End My Shift
                </button>
                <.link
                  navigate={~p"/staff"}
                  class="flex-1 btn btn-secondary bg-slate-200 text-slate-900 rounded-lg px-4 py-2 font-medium text-center"
                >
                  Cancel
                </.link>
              </div>
            </div>
          </div>
        <% end %>
      </main>
    </.staff_shell>
    """
  end

  defp format_time(%DateTime{} = dt) do
    manila = DateTime.add(dt, 8 * 60 * 60, :second)
    Calendar.strftime(manila, "%I:%M %p") |> String.trim_leading("0")
  end

  defp format_time(_), do: "—"

  defp format_duration(%DateTime{} = start, %DateTime{} = end_time) do
    seconds = DateTime.diff(end_time, start)
    hours = div(seconds, 3600)
    minutes = rem(div(seconds, 60), 60)

    case {hours, minutes} do
      {0, m} -> "#{m} min"
      {h, 0} -> "#{h} hr"
      {h, m} -> "#{h}h #{m}m"
    end
  end

  defp format_duration(_, _), do: "—"
end
