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
  alias Espreso.PettyCash
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
    "Petty Cash Purchases",
    "Petty Cash Transfer",
    "Petty Cash Variance",
    "Sales Adjustments",
    "Cash Adjustments",
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

  @petty_cash_headers [
    "Shop Date",
    "Status",
    "Amount",
    "Category",
    "What Was Purchased",
    "Recorded By"
  ]

  @adjustment_headers [
    "Shop Date",
    "Kind",
    "Sales Impact",
    "Drawer Cash Impact",
    "Original Receipt",
    "Original Payment",
    "Reason",
    "Recorded By"
  ]

  def days_headers, do: @days_headers
  def mix_headers, do: @mix_headers
  def cash_out_headers, do: @cash_out_headers
  def petty_cash_headers, do: @petty_cash_headers

  def pack(%Date{} = from_date, %Date{} = to_date) do
    with :ok <- Orders.validate_sales_export_shop_dates(from_date, to_date) do
      closes =
        from_date
        |> Shifts.list_closes_for_shop_dates(to_date)
        |> Enum.group_by(& &1.shop_date)

      opens =
        from_date
        |> Shifts.list_opens_for_shop_dates(to_date)
        |> Enum.group_by(& &1.shop_date)

      cash_outs = CashOuts.list_cash_outs_for_shop_dates(from_date, to_date)
      cash_outs_by_date = Enum.group_by(cash_outs, & &1.shop_date)
      petty_cash_entries = PettyCash.list_for_shop_dates(from_date, to_date)
      petty_cash_by_date = Enum.group_by(petty_cash_entries, & &1.shop_date)
      adjustments = Shifts.list_adjustments_for_shop_dates(from_date, to_date)
      adjustments_by_session = Enum.group_by(adjustments, & &1.shop_session_id)

      days =
        Enum.flat_map(Date.range(from_date, to_date), fn shop_date ->
          rows_for_date(
            shop_date,
            Map.get(opens, shop_date, []),
            Map.get(closes, shop_date, []),
            Map.get(cash_outs_by_date, shop_date, []),
            Map.get(petty_cash_by_date, shop_date, []),
            adjustments_by_session
          )
        end)

      {:ok,
       %{
         from_date: from_date,
         to_date: to_date,
         days: days,
         cash_outs: cash_outs,
         petty_cash_entries: petty_cash_entries,
         adjustments: adjustments
       }}
    end
  end

  def pack(_, _), do: {:error, :invalid_range}

  def build_xlsx(%{from_date: from_date, to_date: to_date} = pack) do
    workbook = %Workbook{
      sheets: [
        days_sheet(pack.days),
        mix_sheet(pack.days),
        cash_outs_sheet(pack.cash_outs),
        petty_cash_sheet(pack.petty_cash_entries),
        adjustments_sheet(pack.adjustments)
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

  def build_pdf(%{
        from_date: from_date,
        to_date: to_date,
        days: days,
        cash_outs: cash_outs,
        petty_cash_entries: petty_cash_entries,
        adjustments: adjustments
      }) do
    lines =
      [
        "Elilai Kafe - Day close",
        "Shop dates #{Date.to_iso8601(from_date)} to #{Date.to_iso8601(to_date)}",
        ""
      ] ++
        Enum.flat_map(days, &pdf_day_lines/1) ++
        ["Cash outs", ""] ++
        pdf_cash_out_lines(cash_outs) ++
        ["Petty-cash purchases", ""] ++
        pdf_petty_cash_lines(petty_cash_entries) ++
        ["Post-close adjustments", ""] ++
        pdf_adjustment_lines(adjustments)

    filename = "elilai-close-#{Date.to_iso8601(from_date)}-#{Date.to_iso8601(to_date)}.pdf"
    {:ok, {filename, PlainPdf.render("Elilai Kafe day close", lines)}}
  end

  defp rows_for_date(date, opens, closes, cash_outs, petty_cash_entries, adjustments_by_session) do
    session_opens = Enum.reject(opens, &is_nil(&1.session_active))
    legacy_open = Enum.find(opens, &is_nil(&1.session_active))
    legacy_close = Enum.find(closes, &is_nil(&1.shop_session_id))
    legacy_cash_outs = Enum.filter(cash_outs, &is_nil(&1.shop_session_id))
    legacy_petty_cash = Enum.filter(petty_cash_entries, &is_nil(&1.shop_session_id))

    session_rows =
      Enum.map(session_opens, fn open ->
        close = Enum.find(closes, &(&1.shop_session_id == open.id))

        day_row(
          date,
          open,
          close,
          Enum.filter(cash_outs, &(&1.shop_session_id == open.id)),
          Enum.filter(petty_cash_entries, &(&1.shop_session_id == open.id)),
          Map.get(adjustments_by_session, open.id, [])
        )
      end)

    legacy_rows =
      if legacy_open || legacy_close || legacy_cash_outs != [] || legacy_petty_cash != [] ||
           session_rows == [] do
        [
          day_row(
            date,
            legacy_open,
            legacy_close,
            legacy_cash_outs,
            legacy_petty_cash,
            []
          )
        ]
      else
        []
      end

    legacy_rows ++ session_rows
  end

  defp day_row(shop_date, open, close, cash_outs, petty_cash_entries, adjustments) do
    recorded_outs = Enum.filter(cash_outs, &(&1.status == "recorded"))

    cash_out_total =
      Enum.reduce(recorded_outs, Decimal.new("0"), fn row, acc ->
        Decimal.add(acc, row.amount || Decimal.new("0"))
      end)

    recorded_petty = Enum.filter(petty_cash_entries, &(&1.status == "recorded"))

    petty_cash_total =
      Enum.reduce(recorded_petty, Decimal.new("0"), fn row, acc ->
        Decimal.add(acc, row.amount || Decimal.new("0"))
      end)

    sales_adjustment_total = adjustment_total(adjustments, :sales_impact)
    adjustment_cash_impact = adjustment_total(adjustments, :drawer_impact)

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
          cash_sales: Shifts.cash_sales_total(close),
          cash_outs: cash_out_total,
          petty_cash_purchases: petty_cash_total,
          petty_cash_transfer: close.petty_cash_transfer,
          petty_cash_variance: close.petty_cash_variance,
          sales_adjustments: sales_adjustment_total,
          adjustment_cash_impact: close.adjustment_cash_impact || adjustment_cash_impact,
          expected: close.expected_cash,
          counted: close.counted_cash,
          variance: close.variance,
          by_via: by_via
        }

      open ->
        breakdown =
          if is_nil(open.session_active),
            do: Orders.paid_breakdown_for_legacy_shop_date(shop_date),
            else: Orders.paid_breakdown_for_session(open)

        cash_sales =
          if open.session_active == true,
            do: Orders.cash_sales_for_session(open),
            else: Shifts.cash_sales_total(breakdown)

        opening = open.opening_cash

        %{
          shop_date: shop_date,
          status: if(open.session_active == true, do: "Open", else: "Incomplete"),
          opened_by: user_name(open.opened_by_user),
          closed_by: "",
          closed_at: nil,
          paid_total: breakdown.total,
          paid_count: breakdown.count,
          opening: opening,
          cash_sales: cash_sales,
          cash_outs: cash_out_total,
          petty_cash_purchases: petty_cash_total,
          petty_cash_transfer: petty_cash_total,
          petty_cash_variance: nil,
          sales_adjustments: sales_adjustment_total,
          adjustment_cash_impact: adjustment_cash_impact,
          expected:
            Shifts.expected_drawer_cash(
              opening,
              cash_sales,
              cash_out_total,
              petty_cash_total,
              adjustment_cash_impact
            ),
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
          petty_cash_purchases: petty_cash_total,
          petty_cash_transfer: nil,
          petty_cash_variance: nil,
          sales_adjustments: Decimal.new("0"),
          adjustment_cash_impact: Decimal.new("0"),
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
          money(day.petty_cash_purchases),
          money(day.petty_cash_transfer),
          money(day.petty_cash_variance),
          money(day.sales_adjustments),
          money(day.adjustment_cash_impact),
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

  defp petty_cash_sheet(entries) do
    rows =
      Enum.map(entries, fn row ->
        [
          Date.to_iso8601(row.shop_date),
          row.status,
          money(row.amount),
          row.category,
          row.note,
          user_name(row.created_by_user)
        ]
      end)

    %Sheet{name: "Petty cash", rows: [@petty_cash_headers | rows]}
  end

  defp adjustments_sheet(adjustments) do
    rows =
      Enum.map(adjustments, fn row ->
        [
          Date.to_iso8601(row.shop_session.shop_date),
          row.kind,
          money(row.sales_impact),
          money(row.drawer_impact),
          row.original_order.number,
          adjustment_payment_label(row),
          row.reason,
          user_name(row.recorded_by_user)
        ]
      end)

    %Sheet{name: "Adjustments", rows: [@adjustment_headers | rows]}
  end

  defp pdf_day_lines(day) do
    [
      "#{Date.to_iso8601(day.shop_date)}  #{day.status}",
      "Opened by #{blank(day.opened_by)}  Closed by #{blank(day.closed_by)} #{datetime_string(day.closed_at)}",
      "Paid #{money(day.paid_total)} (#{day.paid_count} tickets)",
      "Opening #{money(day.opening)}  Cash sales #{money(day.cash_sales)}  Cash outs #{money(day.cash_outs)}  Petty purchases #{money(day.petty_cash_purchases)}  Petty transfer #{money(day.petty_cash_transfer)}",
      "Sales adjustments #{money(day.sales_adjustments)}  Drawer cash adjustments #{money(day.adjustment_cash_impact)}",
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

  defp pdf_petty_cash_lines([]), do: ["None", ""]

  defp pdf_petty_cash_lines(rows) do
    Enum.map(rows, fn row ->
      "#{Date.to_iso8601(row.shop_date)}  #{row.status}  #{money(row.amount)}  #{row.category}  #{row.note}  #{user_name(row.created_by_user)}"
    end) ++ [""]
  end

  defp pdf_adjustment_lines([]), do: ["None", ""]

  defp pdf_adjustment_lines(rows) do
    Enum.map(rows, fn row ->
      "#{Date.to_iso8601(row.shop_session.shop_date)}  #{row.kind}  #{money(row.sales_impact)} sales  #{money(row.drawer_impact)} drawer  #{row.original_order.number}  #{adjustment_payment_label(row)}  #{row.reason}  #{user_name(row.recorded_by_user)}"
    end) ++ [""]
  end

  defp adjustment_total(adjustments, field) do
    Enum.reduce(adjustments, Decimal.new("0"), fn row, total ->
      Decimal.add(total, Map.fetch!(row, field))
    end)
    |> Decimal.round(2)
  end

  defp adjustment_payment_label(%{payment_method: "split", payment_breakdown: breakdown}) do
    breakdown
    |> Map.keys()
    |> Enum.map(&Orders.paid_via_label/1)
    |> Enum.sort()
    |> Enum.join(" + ")
  end

  defp adjustment_payment_label(%{payment_method: method}), do: Orders.paid_via_label(method)

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
