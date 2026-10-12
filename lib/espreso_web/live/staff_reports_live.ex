defmodule EspresoWeb.StaffReportsLive do
  @moduledoc """
  Owner/Manager reports — date range picker for sales, day close, and attendance exports.
  """
  use EspresoWeb, :live_view

  alias Espreso.Accounts.Authorization
  alias Espreso.Menu
  alias Espreso.Orders

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Authorization.can?(user, :reports) do
      today = Orders.shop_date_today()

      {:ok,
       socket
       |> assign(:page_title, "Reports")
       |> assign(:from_date, today)
       |> assign(:to_date, today)
       |> assign(:form_error, nil)
       |> assign_item_sales(today, today, nil), layout: false}
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
     |> assign(:form_error, error)
     |> assign_item_sales(from_date, to_date, error)}
  end

  def handle_event("export", params, socket) do
    report = Map.get(params, "report") || %{}
    kind = Map.get(params, "kind") || "sales"

    case parse_and_validate(report) do
      {from_date, to_date, nil} when not is_nil(from_date) and not is_nil(to_date) ->
        {:noreply,
         socket
         |> assign(:from_date, from_date)
         |> assign(:to_date, to_date)
         |> assign(:form_error, nil)
         |> redirect(to: export_path(kind, from_date, to_date))}

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
    <.staff_shell current={:reports} current_user={@current_user} page_title="Reports" chrome={:bar}>
      <main class="staff-reports" id="staff-reports">
        <header class="staff-reports-head">
          <div>
            <p class="staff-reports-eyebrow">Reports</p>
            <h2>Reports</h2>
            <p>
              Paid item sales and Manager vs Café payout for the selected Manila shop dates,
              plus Excel/PDF exports. Maximum {Orders.max_sales_export_shop_days()} days.
              Owner and manager only.
            </p>
          </div>
        </header>

        <section class="staff-reports-card" aria-label="Export reports">
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

            <div class="staff-reports-actions">
              <button
                type="submit"
                name="kind"
                value="sales"
                id="staff-reports-export"
                class="staff-reports-export-btn"
                disabled={not is_nil(@form_error)}
              >
                Sales Excel
              </button>
              <button
                type="submit"
                name="kind"
                value="close_xlsx"
                id="staff-reports-close-xlsx"
                class="staff-reports-export-btn staff-reports-export-btn--secondary"
                disabled={not is_nil(@form_error)}
              >
                Close Excel
              </button>
              <button
                type="submit"
                name="kind"
                value="close_pdf"
                id="staff-reports-close-pdf"
                class="staff-reports-export-btn staff-reports-export-btn--secondary"
                disabled={not is_nil(@form_error)}
              >
                Close PDF
              </button>
              <button
                type="submit"
                name="kind"
                value="attendance"
                id="staff-reports-attendance-xlsx"
                class="staff-reports-export-btn staff-reports-export-btn--secondary"
                disabled={not is_nil(@form_error)}
              >
                Attendance Excel
              </button>
            </div>

            <p :if={@form_error} class="staff-reports-error" id="staff-reports-error" role="alert">
              {@form_error}
            </p>
          </form>
        </section>

        <section class="staff-reports-card" id="staff-reports-item-sales" aria-label="Sales by item">
          <header class="staff-reports-item-head">
            <h3>Sales by item</h3>
            <p>Paid tickets only. Ranked by peso. Manager food is marked on the ticket.</p>
          </header>
          <p :if={@item_sales == []} class="staff-reports-item-empty" id="staff-reports-item-empty">
            No paid items in this range.
          </p>
          <table :if={@item_sales != []} class="staff-reports-item-table">
            <thead>
              <tr>
                <th>Item</th>
                <th>Qty</th>
                <th>Sales</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @item_sales}>
                <td class="staff-reports-item-name">
                  <span>{item.name}</span>
                  <span :if={item_owner(item)} class="staff-reports-item-owner">
                    {item_owner(item)}
                  </span>
                </td>
                <td class="staff-reports-item-qty">{item_qty(item.quantity)}</td>
                <td class="staff-reports-item-total">{peso(item.total)}</td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <th>Total</th>
                <td class="staff-reports-item-qty">{item_qty_total(@item_sales)}</td>
                <td class="staff-reports-item-total">{peso(item_sales_total(@item_sales))}</td>
              </tr>
            </tfoot>
          </table>
        </section>

        <section class="staff-reports-card" id="staff-reports-payout" aria-label="Payout">
          <header class="staff-reports-item-head">
            <h3>Payout</h3>
            <p>Settle Manager food vs Café from paid tickets.</p>
          </header>
          <p
            :if={@item_payouts == []}
            class="staff-reports-item-empty"
            id="staff-reports-payout-empty"
          >
            No paid items in this range.
          </p>
          <table :if={@item_payouts != []} class="staff-reports-item-table">
            <thead>
              <tr>
                <th>Share</th>
                <th>Qty</th>
                <th>Payout</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @item_payouts}>
                <td class="staff-reports-item-name">{payout_owner(row)}</td>
                <td class="staff-reports-item-qty">{item_qty(row.quantity)}</td>
                <td class="staff-reports-item-total">{peso(row.total)}</td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <th>Total</th>
                <td class="staff-reports-item-qty">{item_qty_total(@item_payouts)}</td>
                <td class="staff-reports-item-total">{peso(item_sales_total(@item_payouts))}</td>
              </tr>
            </tfoot>
          </table>
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

  defp export_path("close_xlsx", from_date, to_date),
    do:
      ~p"/staff/reports/export/close.xlsx?from=#{Date.to_iso8601(from_date)}&to=#{Date.to_iso8601(to_date)}"

  defp export_path("close_pdf", from_date, to_date),
    do:
      ~p"/staff/reports/export/close.pdf?from=#{Date.to_iso8601(from_date)}&to=#{Date.to_iso8601(to_date)}"

  defp export_path("attendance", from_date, to_date),
    do:
      ~p"/staff/reports/export/attendance.xlsx?from=#{Date.to_iso8601(from_date)}&to=#{Date.to_iso8601(to_date)}"

  defp export_path(_kind, from_date, to_date),
    do:
      ~p"/staff/reports/export?from=#{Date.to_iso8601(from_date)}&to=#{Date.to_iso8601(to_date)}"

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

  defp assign_item_sales(socket, from_date, to_date, nil)
       when not is_nil(from_date) and not is_nil(to_date) do
    rows = Orders.paid_item_sales(from: from_date, to: to_date)

    socket
    |> assign(:item_sales, rows)
    |> assign(:item_payouts, Orders.paid_item_payouts(from: from_date, to: to_date))
  end

  defp assign_item_sales(socket, _, _, _) do
    socket
    |> assign(:item_sales, [])
    |> assign(:item_payouts, [])
  end

  defp peso(amount) do
    amount
    |> Menu.format_price()
    |> String.replace(~r/^P(?=[\d,])/, "₱")
  end

  defp item_qty(qty) when is_integer(qty), do: qty
  defp item_qty(%Decimal{} = qty), do: qty |> Decimal.round(0) |> Decimal.to_integer()
  defp item_qty(_), do: 0

  defp item_owner(%{item_owner: owner}) when is_binary(owner) and owner != "" do
    case String.downcase(owner) do
      "manager" -> "Manager"
      _ -> owner
    end
  end

  defp item_owner(_), do: nil

  defp payout_owner(row), do: item_owner(row) || "Café"

  defp item_qty_total(rows) when is_list(rows) do
    Enum.reduce(rows, 0, fn row, acc -> acc + item_qty(row.quantity) end)
  end

  defp item_sales_total(rows) when is_list(rows) do
    Enum.reduce(rows, Decimal.new("0"), fn row, acc ->
      Decimal.add(acc, row.total || Decimal.new("0"))
    end)
  end
end
