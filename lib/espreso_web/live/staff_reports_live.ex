defmodule EspresoWeb.StaffReportsLive do
  @moduledoc """
  Owner/Manager Sales Report — date range picker and Excel export.
  """
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Authorization.can?(user, :reports) do
      today = Orders.shop_date_today()

      {:ok,
       socket
       |> assign(:page_title, "Sales Report")
       |> assign(:from_date, today)
       |> assign(:to_date, today)
       |> assign(:form_error, nil), layout: false}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don’t have access to reports.")
       |> push_navigate(to: ~p"/staff"), layout: false}
    end
  end

  @impl true
  def handle_event("validate", %{"report" => params}, socket) do
    {from_date, to_date, error} = parse_and_validate(params)

    {:noreply,
     socket
     |> assign(:from_date, from_date || socket.assigns.from_date)
     |> assign(:to_date, to_date || socket.assigns.to_date)
     |> assign(:form_error, error)}
  end

  def handle_event("export", %{"report" => params}, socket) do
    case parse_and_validate(params) do
      {from_date, to_date, nil} when not is_nil(from_date) and not is_nil(to_date) ->
        {:noreply,
         socket
         |> assign(:from_date, from_date)
         |> assign(:to_date, to_date)
         |> assign(:form_error, nil)
         |> redirect(
           to: ~p"/staff/reports/export?from=#{Date.to_iso8601(from_date)}&to=#{Date.to_iso8601(to_date)}"
         )}

      {from_date, to_date, error} ->
        {:noreply,
         socket
         |> assign(:from_date, from_date || socket.assigns.from_date)
         |> assign(:to_date, to_date || socket.assigns.to_date)
         |> assign(:form_error, error || "Enter a valid Date From and Date To.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.staff_shell current={:reports} current_user={@current_user} page_title="Sales Report" chrome={:bar}>
      <main class="staff-reports" id="staff-reports">
        <header class="staff-reports-head">
          <div>
            <p class="staff-reports-eyebrow">Reports</p>
            <h2>Sales Report</h2>
            <p>
              Export paid sales for a Manila shop-date range as an Excel file
              (Sales + Items sheets). Maximum {Orders.max_sales_export_shop_days()} days.
            </p>
          </div>
        </header>

        <section class="staff-reports-card" aria-label="Export sales">
          <form id="staff-reports-export-form" phx-change="validate" phx-submit="export">
            <div class="staff-reports-fields">
              <label class="staff-reports-field">
                <span>Date From</span>
                <input
                  type="date"
                  name="report[from]"
                  id="staff-reports-from"
                  value={Date.to_iso8601(@from_date)}
                  required
                />
              </label>

              <label class="staff-reports-field">
                <span>Date To</span>
                <input
                  type="date"
                  name="report[to]"
                  id="staff-reports-to"
                  value={Date.to_iso8601(@to_date)}
                  required
                />
              </label>
            </div>

            <p :if={@form_error} class="staff-reports-error" id="staff-reports-error" role="alert">
              {@form_error}
            </p>

            <button
              type="submit"
              id="staff-reports-export"
              class="staff-reports-export-btn"
              disabled={not is_nil(@form_error)}
            >
              Export Excel
            </button>
          </form>
        </section>
      </main>
    </.staff_shell>
    """
  end

  defp parse_and_validate(params) when is_map(params) do
    from_raw = Map.get(params, "from") || Map.get(params, :from)
    to_raw = Map.get(params, "to") || Map.get(params, :to)

    with {:ok, from_date} <- parse_date(from_raw),
         {:ok, to_date} <- parse_date(to_raw),
         :ok <- Orders.validate_sales_export_shop_dates(from_date, to_date) do
      {from_date, to_date, nil}
    else
      {:error, :invalid_date} ->
        {parse_date_or_nil(from_raw), parse_date_or_nil(to_raw),
         "Enter a valid Date From and Date To."}

      {:error, :invalid_range} ->
        {parse_date_or_nil(from_raw), parse_date_or_nil(to_raw),
         "Date From must be on or before Date To."}

      {:error, :range_too_large} ->
        {parse_date_or_nil(from_raw), parse_date_or_nil(to_raw),
         "Choose a date range of #{Orders.max_sales_export_shop_days()} days or fewer."}
    end
  end

  defp parse_and_validate(_), do: {nil, nil, "Enter a valid Date From and Date To."}

  defp parse_date(nil), do: {:error, :invalid_date}
  defp parse_date(""), do: {:error, :invalid_date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(_), do: {:error, :invalid_date}

  defp parse_date_or_nil(value) do
    case parse_date(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
