defmodule Espreso.Reports.CloseExport do
  @moduledoc """
  Owner/Manager day-close workbook and printable PDF.

  Uses sealed `ShiftClose` snapshots when present; otherwise live paid mix
  plus opening cash and cash outs. Does not change settlement.
  """

  alias Elixlsx.{Sheet, Workbook}
  alias Espreso.CashOuts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Reports.PlainPdf
  alias Espreso.Shifts

  @vias ~w(cash gcash maya counter paymongo)

  @days_headers [
    "Shop Date",
    "Status",
    "Opened By",
    "Closed By",
    "Closed At",
    "Paid Total",
    "Paid Tickets",
    "Opening Cash",
    "Cash Sales",
    "Cash Outs",
    "Expected",
    "Counted",
    "Variance"
  ]

  @mix_headers ["Shop Date", "Paid Via", "Total", "Tickets"]

  @cash_out_headers [
    "Shop Date",
    "Status",
    "Amount",
    "Category",
    "Note",
    "Recorded By"
  ]

  def days_headers, do: @days_headers
  def mix_headers, do: @mix_headers
  def cash_out_headers, do: @cash_out_headers

  def pack(%Date{} = from_date, %Date{} = to_date) do
    with :ok <- Orders.validate_sales_export_shop_dates(from_date, to_date) do
      closes =
        from_date
        |> Shifts.list_closes_for_shop_dates(to_date)
        |> Map.new(&{&1.shop_date, &1})

      opens =
        from_date
        |> Shifts.list_opens_for_shop_dates(to_date)
        |> Map.new(&{&1.shop_date, &1})

      cash_outs = CashOuts.list_cash_outs_for_shop_dates(from_date, to_date)
      cash_outs_by_date = Enum.group_by(cash_outs, & &1.shop_date)

      days =
        Enum.map(Date.range(from_date, to_date), fn shop_date ->
          day_row(
            shop_date,
            Map.get(opens, shop_date),
            Map.get(closes, shop_date),
            Map.get(cash_outs_by_date, shop_date, [])
          )
        end)

      {:ok, %{from_date: from_date, to_date: to_date, days: days, cash_outs: cash_outs}}
    end
  end

  def pack(_, _), do: {:error, :invalid_range}

  def build_xlsx(%{from_date: from_date, to_date: to_date} = pack) do
    workbook = %Workbook{
      sheets: [
        days_sheet(pack.days),
        mix_sheet(pack.days),
        cash_outs_sheet(pack.cash_outs)
      ]
    }

    filename = "elilai-close-#{Date.to_iso8601(from_date)}-#{Date.to_iso8601(to_date)}.xlsx"

    case Elixlsx.write_to_memory(workbook, filename) do
      {:ok, {_name, binary}} when is_binary(binary) ->
        {:ok, {filename, binary}}

      {:ok, {name, binary}} when is_list(name) and is_binary(binary) ->
        {:ok, {List.to_string(name), binary}}

      other ->
        {:error, {:xlsx_write_failed, other}}
    end
  end

  def build_pdf(%{from_date: from_date, to_date: to_date, days: days, cash_outs: cash_outs}) do
    lines =
      [
        "Elilai Kafe - Day close",
        "Shop dates #{Date.to_iso8601(from_date)} to #{Date.to_iso8601(to_date)}",
        ""
      ] ++
        Enum.flat_map(days, &pdf_day_lines/1) ++
        ["Cash outs", ""] ++
        pdf_cash_out_lines(cash_outs)

    filename = "elilai-close-#{Date.to_iso8601(from_date)}-#{Date.to_iso8601(to_date)}.pdf"
    {:ok, {filename, PlainPdf.render("Elilai Kafe day close", lines)}}
  end

  defp day_row(shop_date, open, close, cash_outs) do
    recorded_outs = Enum.filter(cash_outs, &(&1.status == "recorded"))

    cash_out_total =
      Enum.reduce(recorded_outs, Decimal.new("0"), fn row, acc ->
        Decimal.add(acc, row.amount || Decimal.new("0"))
      end)

    cond do
      close ->
        by_via = close.by_via || %{}

        %{
          shop_date: shop_date,
          status: "Closed",
          opened_by: user_name(open && open.opened_by_user),
          closed_by: user_name(close.closed_by_user),
          closed_at: close.closed_at,
          paid_total: close.system_total,
          paid_count: close.system_count,
          opening: close.opening_cash,
          cash_sales: Shifts.cash_sales_total(%{by_via: by_via}),
          cash_outs: cash_out_total,
          expected: close.expected_cash,
          counted: close.counted_cash,
          variance: close.variance,
          by_via: by_via
        }

      open ->
        breakdown = Orders.paid_breakdown_for_shop_date(shop_date)
        cash_sales = Shifts.cash_sales_total(breakdown)
        opening = open.opening_cash

        %{
          shop_date: shop_date,
          status: "Open",
          opened_by: user_name(open.opened_by_user),
          closed_by: "",
          closed_at: nil,
          paid_total: breakdown.total,
          paid_count: breakdown.count,
          opening: opening,
          cash_sales: cash_sales,
          cash_outs: cash_out_total,
          expected: Shifts.expected_drawer_cash(opening, cash_sales, cash_out_total),
          counted: nil,
          variance: nil,
          by_via: breakdown.by_via
        }

      true ->
        %{
          shop_date: shop_date,
          status: "Not open",
          opened_by: "",
          closed_by: "",
          closed_at: nil,
          paid_total: Decimal.new("0"),
          paid_count: 0,
          opening: nil,
          cash_sales: Decimal.new("0"),
          cash_outs: cash_out_total,
          expected: nil,
          counted: nil,
          variance: nil,
          by_via: %{}
        }
    end
  end

  defp days_sheet(days) do
    rows =
      Enum.map(days, fn day ->
        [
          Date.to_iso8601(day.shop_date),
          day.status,
          day.opened_by,
          day.closed_by,
          datetime_string(day.closed_at),
          money(day.paid_total),
          day.paid_count || 0,
          money(day.opening),
          money(day.cash_sales),
          money(day.cash_outs),
          money(day.expected),
          money(day.counted),
          money(day.variance)
        ]
      end)

    %Sheet{name: "Days", rows: [@days_headers | rows]}
  end

  defp mix_sheet(days) do
    rows =
      Enum.flat_map(days, fn day ->
        Enum.map(@vias, fn via ->
          {total, count} = via_entry(day.by_via, via)

          [
            Date.to_iso8601(day.shop_date),
            Orders.paid_via_label(via),
            money(total),
            count
          ]
        end)
      end)

    %Sheet{name: "Payment mix", rows: [@mix_headers | rows]}
  end

  defp cash_outs_sheet(cash_outs) do
    rows =
      Enum.map(cash_outs, fn row ->
        [
          Date.to_iso8601(row.shop_date),
          row.status,
          money(row.amount),
          row.category,
          row.note || "",
          user_name(row.created_by_user)
        ]
      end)

    %Sheet{name: "Cash outs", rows: [@cash_out_headers | rows]}
  end

  defp pdf_day_lines(day) do
    [
      "#{Date.to_iso8601(day.shop_date)}  #{day.status}",
      "Opened by #{blank(day.opened_by)}  Closed by #{blank(day.closed_by)} #{datetime_string(day.closed_at)}",
      "Paid #{money(day.paid_total)} (#{day.paid_count} tickets)",
      "Opening #{money(day.opening)}  Cash sales #{money(day.cash_sales)}  Cash outs #{money(day.cash_outs)}",
      "Expected #{money(day.expected)}  Counted #{money(day.counted)}  Variance #{money(day.variance)}",
      mix_line(day.by_via),
      ""
    ]
  end

  defp pdf_cash_out_lines([]), do: ["None", ""]

  defp pdf_cash_out_lines(rows) do
    Enum.map(rows, fn row ->
      "#{Date.to_iso8601(row.shop_date)}  #{row.status}  #{money(row.amount)}  #{row.category}  #{row.note || ""}  #{user_name(row.created_by_user)}"
    end) ++ [""]
  end

  defp mix_line(by_via) do
    @vias
    |> Enum.map(fn via ->
      {total, count} = via_entry(by_via, via)
      "#{Orders.paid_via_label(via)} #{money(total)} (#{count})"
    end)
    |> Enum.join("  ")
  end

  defp via_entry(by_via, via) when is_map(by_via) do
    entry = Map.get(by_via, via) || %{}
    total = Map.get(entry, :total) || Map.get(entry, "total")
    count = Map.get(entry, :count) || Map.get(entry, "count") || 0
    {decimalize(total), count}
  end

  defp via_entry(_, _), do: {Decimal.new("0"), 0}

  defp user_name(%{name: name}) when is_binary(name), do: name
  defp user_name(_), do: ""

  defp blank(""), do: "-"
  defp blank(nil), do: "-"
  defp blank(value), do: value

  defp datetime_string(%DateTime{} = at) do
    at
    |> DateTime.add(8 * 60 * 60, :second)
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp datetime_string(_), do: ""

  defp money(nil), do: ""
  defp money(%Decimal{} = amount), do: Menu.format_price(amount)
  defp money(amount) when is_binary(amount), do: Menu.format_price(Decimal.new(amount))
  defp money(amount) when is_integer(amount), do: Menu.format_price(Decimal.new(amount))
  defp money(_), do: ""

  defp decimalize(nil), do: Decimal.new("0")
  defp decimalize(%Decimal{} = value), do: value
  defp decimalize(value) when is_binary(value), do: Decimal.new(value)
  defp decimalize(value) when is_integer(value), do: Decimal.new(value)
  defp decimalize(_), do: Decimal.new("0")
end
