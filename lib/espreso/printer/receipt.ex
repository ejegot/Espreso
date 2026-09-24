defmodule Espreso.Printer.Receipt do
  @moduledoc false

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Printer.EscPos
  alias Espreso.Shifts

  @doc """
  Builds an ESC/POS receipt.

  Options:
  - `:staff_name` — logged-in cashier name
  - `:cash_tendered` / `:change` — optional Decimals for cash lines
  """
  def build(%Order{} = order, opts \\ []) do
    items = List.wrap(Map.get(order, :items) || [])
    paid_via = order.paid_via || "cash"
    staff_name = opts |> Keyword.get(:staff_name) |> blank_to_nil()
    conf = receipt_config()

    EscPos.join(
      [
        EscPos.init(),
        brand_header(),
        EscPos.text_line("LILAC, MARIKINA"),
        EscPos.bold_off(),
        EscPos.text_line(conf.address),
        EscPos.text_line("Owned and Operated by: Elilai Kafe"),
        EscPos.feed(1),
        EscPos.align_left(),
        EscPos.bold_on(),
        EscPos.text_line(employee_line(staff_name)),
        EscPos.bold_off(),
        EscPos.separator(),
        EscPos.bold_on(),
        EscPos.text_line(fulfillment_line(order)),
        EscPos.bold_off(),
        EscPos.separator(),
        EscPos.bold_on(),
        EscPos.text_line("Order #{order.number}"),
        EscPos.text_line(customer_line(order)),
        EscPos.bold_off(),
        EscPos.separator()
      ] ++
        Enum.flat_map(items, &item_lines/1) ++
        [
          EscPos.separator(),
          EscPos.bold_on(),
          EscPos.size_double_height(),
          EscPos.columns("TOTAL", money(order.total)),
          EscPos.size_normal()
        ] ++
        payment_lines(order, paid_via, opts) ++
        [
          EscPos.bold_off(),
          EscPos.separator(),
          EscPos.align_center()
        ] ++
        wifi_block(conf) ++
        [
          EscPos.align_left(),
          EscPos.columns(timestamp_line(order), "##{order.number}"),
          EscPos.feed(2),
          EscPos.cut()
        ]
    )
  end

  @doc """
  Compact kitchen ticket — items + notes, no prices / Wi‑Fi.
  """
  def build_kitchen(%Order{} = order, opts \\ []) do
    items = List.wrap(Map.get(order, :items) || [])
    staff_name = opts |> Keyword.get(:staff_name) |> blank_to_nil()

    EscPos.join(
      [
        EscPos.init(),
        EscPos.align_center(),
        EscPos.bold_on(),
        EscPos.size_double_height(),
        EscPos.text_line("KITCHEN"),
        EscPos.size_normal(),
        brand_header(),
        EscPos.bold_off(),
        EscPos.align_left(),
        EscPos.bold_on(),
        EscPos.size_double_height(),
        EscPos.text_line(order.number),
        EscPos.size_normal(),
        EscPos.text_line(fulfillment_line(order)),
        EscPos.text_line(customer_line(order)),
        EscPos.bold_off()
      ] ++
        if(staff_name, do: [EscPos.text_line("Cashier: #{staff_name}")], else: []) ++
        [
          EscPos.separator()
        ] ++
        Enum.flat_map(items, &kitchen_item_lines/1) ++
        kitchen_notes(order) ++
        [
          EscPos.separator(),
          EscPos.feed(2),
          EscPos.cut()
        ]
    )
  end

  @doc """
  End-of-day drawer report for the sealed `ShiftClose` snapshot.
  """
  def build_day_report(close, opts \\ []) do
    staff_name = opts |> Keyword.get(:staff_name) |> blank_to_nil()
    shop_date = close.shop_date

    date_label =
      if match?(%Date{}, shop_date), do: Calendar.strftime(shop_date, "%b %-d, %Y"), else: ""

    variance = close.variance
    variance_label = variance_label(variance)
    cash_sales = cash_sales_from_close(close)
    cash_outs = cash_outs_from_close(close, opts)
    refunds = refunds_from_opts(opts)

    EscPos.join(
      [
        EscPos.init(),
        brand_header(),
        EscPos.text_line("DAY REPORT"),
        EscPos.bold_off(),
        EscPos.text_line("Elilai Kafe"),
        EscPos.text_line(date_label),
        EscPos.feed(1),
        EscPos.align_left(),
        EscPos.separator(),
        EscPos.align_center(),
        EscPos.text_line("CASH DRAWER"),
        EscPos.align_left(),
        EscPos.columns("Opening cash", money(close.opening_cash)),
        EscPos.columns("Cash sales", money(cash_sales))
      ] ++
        optional_money_line("Cash outs", cash_outs) ++
        [
          EscPos.columns("Expected", money(close.expected_cash)),
          EscPos.columns("Counted", money(close.counted_cash)),
          EscPos.bold_on(),
          EscPos.columns(variance_label, money(variance)),
          EscPos.bold_off(),
          EscPos.separator(),
          EscPos.align_center(),
          EscPos.text_line("SALES"),
          EscPos.align_left(),
          EscPos.columns("Paid", money(close.system_total)),
          EscPos.text_line("#{close.system_count || 0} orders")
        ] ++
        optional_money_line("Refunds", refunds) ++
        day_report_via_lines(close) ++
        [
          EscPos.separator(),
          EscPos.text_line(if(staff_name, do: "Closed by #{staff_name}", else: "Closed")),
          EscPos.text_line(Shifts.format_closed_at(close.closed_at)),
          EscPos.feed(2),
          EscPos.cut()
        ]
    )
  end

  defp cash_sales_from_close(close), do: Shifts.cash_sales_total(close)

  defp cash_outs_from_close(close, opts) do
    case Keyword.get(opts, :cash_outs) do
      %Decimal{} = amount -> amount
      _ -> Shifts.implied_cash_outs(close)
    end
  end

  defp refunds_from_opts(opts) do
    case Keyword.get(opts, :refunds) do
      %Decimal{} = amount -> amount
      _ -> Decimal.new("0")
    end
  end

  defp optional_money_line(label, amount) do
    if is_nil(amount) or decimal_zero?(amount) do
      []
    else
      [EscPos.columns(label, money(amount))]
    end
  end

  defp variance_label(%Decimal{} = variance) do
    case Decimal.compare(variance, 0) do
      :gt -> "Over"
      :lt -> "Short"
      :eq -> "Even"
    end
  end

  defp variance_label(_), do: "Variance"

  defp day_report_via_lines(%{by_via: by_via}) when is_map(by_via) do
    Enum.flat_map(~w(cash gcash maya), fn via ->
      entry = Map.get(by_via, via, %{})
      total = Map.get(entry, "total") || Map.get(entry, :total)

      if is_nil(total) or decimal_zero?(total) do
        []
      else
        [EscPos.columns(Orders.paid_via_label(via), money(total))]
      end
    end)
  end

  defp day_report_via_lines(_), do: []

  defp decimal_zero?(value) do
    case value do
      %Decimal{} = d ->
        Decimal.compare(d, 0) == :eq

      other ->
        case Decimal.parse(to_string(other)) do
          {d, _} -> Decimal.compare(d, 0) == :eq
          :error -> true
        end
    end
  end

  defp payment_lines(order, paid_via, opts) do
    split_lines = split_payment_lines(order)

    tender_lines = cash_change_lines(order, opts)

    cond do
      split_lines != [] ->
        split_lines ++ tender_lines

      tender_lines != [] ->
        tender_lines

      true ->
        [EscPos.columns(Orders.paid_via_label(paid_via), money(order.total))]
    end
  end

  defp split_payment_lines(%{payment_splits: splits}) when is_list(splits) and splits != [] do
    splits
    |> Enum.sort_by(fn
      %{paid_via: "cash"} -> 0
      _ -> 1
    end)
    |> Enum.map(fn split ->
      EscPos.columns(Orders.paid_via_label(split.paid_via), money(split.amount))
    end)
  end

  defp split_payment_lines(_), do: []

  defp cash_change_lines(order, opts) do
    tendered = Keyword.get(opts, :cash_tendered) || order.cash_tendered
    change = Keyword.get(opts, :change) || order.change_due

    if match?(%Decimal{}, tendered) and match?(%Decimal{}, change) do
      [
        EscPos.columns("Tendered", money(tendered)),
        EscPos.columns("Change", money(change))
      ]
    else
      []
    end
  end

  defp kitchen_item_lines(item) do
    qty = item.quantity || 1
    name = Orders.prep_item_name(item)

    [
      EscPos.bold_on(),
      EscPos.size_double_height(),
      EscPos.text_line("#{qty}x #{name}"),
      EscPos.size_normal(),
      EscPos.bold_off()
    ]
  end

  defp kitchen_notes(%{notes: notes}) when is_binary(notes) do
    trimmed = String.trim(notes)

    if trimmed == "" do
      []
    else
      [
        EscPos.separator(),
        EscPos.bold_on(),
        EscPos.text_line("NOTE"),
        EscPos.bold_off(),
        EscPos.text_line(trimmed)
      ]
    end
  end

  defp kitchen_notes(_), do: []

  defp receipt_config do
    conf = Application.get_env(:espreso, Espreso.Printer, [])

    %{
      address: Keyword.get(conf, :receipt_address, "84 Lilac St., Marikina City"),
      wifi_title: Keyword.get(conf, :wifi_title, "COFFEESPOT LILAC WI-FI"),
      wifi_ssid: Keyword.get(conf, :wifi_ssid, "CoffeeSpot_Guest"),
      wifi_password: Keyword.get(conf, :wifi_password, "SPOT3333"),
      wifi_note: Keyword.get(conf, :wifi_note, "Access is valid for 2 Hours per purchase."),
      wifi_thanks: Keyword.get(conf, :wifi_thanks, "Thank you for fueling your hustle with us!")
    }
  end

  defp shop_name do
    case Application.get_env(:espreso, :receipt_shop_name) do
      name when is_binary(name) and name != "" -> name
      _ -> "CoffeeSpot"
    end
  end

  @doc false
  def brand_header do
    mark = EscPos.shop_mark()

    if mark == <<>> do
      [
        EscPos.align_center(),
        EscPos.bold_on(),
        EscPos.size_double_height(),
        EscPos.text_line(shop_name()),
        EscPos.size_normal()
      ]
    else
      [
        EscPos.align_center(),
        mark,
        EscPos.feed(1),
        EscPos.bold_on()
      ]
    end
  end

  defp employee_line(nil), do: "Employee: Staff"
  defp employee_line(name), do: "Employee: #{name}"

  defp customer_line(%{customer_name: name}) when is_binary(name) and name != "",
    do: "Name: #{name}"

  defp customer_line(_), do: "Name: Walk-in"

  defp fulfillment_line(%{fulfillment: "dine_in"}), do: "Dine-in"
  defp fulfillment_line(_), do: "Takeout"

  defp timestamp_line(%{settled_at: %DateTime{} = at}), do: format_shop_timestamp(at)
  defp timestamp_line(%{inserted_at: %DateTime{} = at}), do: format_shop_timestamp(at)

  defp timestamp_line(%{inserted_at: %NaiveDateTime{} = at}) do
    hour12 = rem(at.hour + 11, 12) + 1
    ampm = if at.hour >= 12, do: "PM", else: "AM"
    min = at.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{at.month}/#{at.day}/#{rem(at.year, 100)} #{hour12}:#{min} #{ampm}"
  end

  defp timestamp_line(_), do: timestamp_line(%{inserted_at: NaiveDateTime.local_now()})

  defp format_shop_timestamp(%DateTime{} = at) do
    at
    |> DateTime.add(8 * 60 * 60, :second)
    |> then(&timestamp_line(%{inserted_at: DateTime.to_naive(&1)}))
  end

  defp item_lines(item) do
    qty = item.quantity || 1
    unit = money(item.unit_price)
    line = money(item.line_total || Decimal.mult(item.unit_price || Decimal.new(0), qty))
    name = Orders.prep_item_name(item)

    [
      EscPos.bold_on(),
      EscPos.columns(name, line),
      EscPos.bold_off(),
      EscPos.text_line("  #{qty} x #{unit}")
    ]
  end

  defp wifi_block(%{wifi_ssid: ssid, wifi_password: password} = conf)
       when is_binary(ssid) and ssid != "" and is_binary(password) and password != "" do
    [
      EscPos.bold_on(),
      EscPos.text_line(conf.wifi_title),
      EscPos.text_line("Today's Network: #{ssid}"),
      EscPos.text_line("Today's Access Code: #{password}"),
      EscPos.bold_off(),
      EscPos.text_line("*#{conf.wifi_note}"),
      EscPos.text_line(conf.wifi_thanks),
      EscPos.separator()
    ]
  end

  defp wifi_block(_), do: [EscPos.text_line("Thank you!"), EscPos.separator()]

  # Thermal-safe ASCII "P" + always two decimals (P180.00).
  defp money(nil), do: "P0.00"

  defp money(amount) do
    rounded = amount |> Decimal.round(2) |> Decimal.to_string(:normal)

    formatted =
      case String.split(rounded, ".") do
        [whole] -> "#{add_thousands(whole)}.00"
        [whole, frac] -> "#{add_thousands(whole)}.#{String.pad_trailing(frac, 2, "0")}"
      end

    "P#{formatted}"
  end

  defp add_thousands(whole) when is_binary(whole) do
    whole
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_to_nil(_), do: nil
end
