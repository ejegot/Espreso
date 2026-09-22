defmodule Espreso.Reports.AttendanceExport do
  @moduledoc """
  Owner/Manager staff attendance Excel for a Manila shop-date range.
  """

  alias Elixlsx.{Sheet, Workbook}
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  @headers [
    "Shop Date",
    "Staff",
    "Started",
    "Ended",
    "Status",
    "End Reason",
    "Paid POS Orders",
    "Paid POS Total"
  ]

  def headers, do: @headers

  def pack(%Date{} = from_date, %Date{} = to_date) do
    with :ok <- Orders.validate_sales_export_shop_dates(from_date, to_date) do
      rows =
        Enum.flat_map(Date.range(from_date, to_date), fn shop_date ->
          shop_date
          |> StaffShifts.list_shifts_for_shop_day()
          |> Enum.map(fn %StaffShift{} = shift ->
            sales = Orders.sales_summary_for_staff_shift(shift)

            %{
              shop_date: shop_date,
              name: employee_name(shift),
              started_at: shift.started_at,
              ended_at: shift.ended_at,
              status: if(is_nil(shift.ended_at), do: "Open", else: "Completed"),
              end_reason: shift.end_reason || "",
              order_count: sales.order_count,
              total: sales.total
            }
          end)
        end)

      {:ok, %{from_date: from_date, to_date: to_date, rows: rows}}
    end
  end

  def pack(_, _), do: {:error, :invalid_range}

  def build_xlsx(%{from_date: from_date, to_date: to_date, rows: rows}) do
    sheet_rows =
      Enum.map(rows, fn row ->
        [
          Date.to_iso8601(row.shop_date),
          row.name,
          datetime_string(row.started_at),
          datetime_string(row.ended_at),
          row.status,
          row.end_reason,
          row.order_count,
          Menu.format_price(row.total)
        ]
      end)

    workbook = %Workbook{
      sheets: [%Sheet{name: "Attendance", rows: [@headers | sheet_rows]}]
    }

    filename = "elilai-attendance-#{Date.to_iso8601(from_date)}-#{Date.to_iso8601(to_date)}.xlsx"

    case Elixlsx.write_to_memory(workbook, filename) do
      {:ok, {_name, binary}} when is_binary(binary) ->
        {:ok, {filename, binary}}

      {:ok, {name, binary}} when is_list(name) and is_binary(binary) ->
        {:ok, {List.to_string(name), binary}}

      other ->
        {:error, {:xlsx_write_failed, other}}
    end
  end

  defp employee_name(%StaffShift{user: %{name: name}}) when is_binary(name), do: name
  defp employee_name(_), do: "Staff"

  defp datetime_string(%DateTime{} = at) do
    at
    |> DateTime.add(8 * 60 * 60, :second)
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp datetime_string(_), do: ""
end
