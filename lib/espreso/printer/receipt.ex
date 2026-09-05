defmodule Espreso.Printer.Receipt do
  @moduledoc false

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Printer.EscPos

  @doc """
  Builds an ESC/POS receipt.

  Options:
  - `:staff_name` — logged-in cashier name
  """
  def build(%Order{} = order, opts \\ []) do
    items = List.wrap(Map.get(order, :items) || [])
    paid_via = order.paid_via || "cash"
    staff_name = opts |> Keyword.get(:staff_name) |> blank_to_nil()
    conf = receipt_config()

    EscPos.join(
      [
        EscPos.init(),
        EscPos.align_center(),
        EscPos.bold_on(),
        EscPos.size_double_height(),
        EscPos.text_line(shop_name()),
        EscPos.size_normal(),
        EscPos.text_line("LILAC, MARIKINA"),
        EscPos.bold_off(),
        EscPos.text_line(conf.address),
        EscPos.text_line("Owned and Operated by: Elilai Kafe"),
        EscPos.feed(2),
        EscPos.align_left(),
        EscPos.bold_on(),
        EscPos.text_line(employee_line(staff_name)),
        EscPos.bold_off(),
        EscPos.feed(1),
        EscPos.separator(),
        EscPos.bold_on(),
        EscPos.text_line(fulfillment_line(order)),
        EscPos.bold_off(),
        EscPos.separator(),
        EscPos.feed(1),
        EscPos.bold_on(),
        EscPos.text_line("Order #{order.number}"),
        EscPos.text_line(customer_line(order)),
        EscPos.bold_off(),
        EscPos.feed(1),
        EscPos.separator(),
        EscPos.feed(1)
      ] ++
        Enum.flat_map(items, &item_lines/1) ++
        [
          EscPos.separator(),
          EscPos.feed(1),
          EscPos.bold_on(),
          EscPos.size_double_height(),
          EscPos.columns("TOTAL", money(order.total)),
          EscPos.size_normal(),
          EscPos.columns(Orders.paid_via_label(paid_via), money(order.total)),
          EscPos.bold_off(),
          EscPos.feed(1),
          EscPos.separator(),
          EscPos.feed(1),
          EscPos.align_center()
        ] ++
        wifi_block(conf) ++
        [
          EscPos.feed(1),
          EscPos.align_left(),
          EscPos.columns(timestamp_line(order), "##{order.number}"),
          EscPos.feed(3),
          EscPos.cut()
        ]
    )
  end

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

  defp employee_line(nil), do: "Employee: Staff"
  defp employee_line(name), do: "Employee: #{name}"

  defp customer_line(%{customer_name: name}) when is_binary(name) and name != "",
    do: "Name: #{name}"

  defp customer_line(_), do: "Name: Walk-in"

  defp fulfillment_line(%{fulfillment: "dine_in", table_number: table})
       when is_binary(table) and table != "",
       do: "Dine in - Table #{table}"

  defp fulfillment_line(%{fulfillment: "dine_in"}), do: "Dine in"
  defp fulfillment_line(_), do: "Pickup"

  defp timestamp_line(%{inserted_at: %NaiveDateTime{} = at}) do
    hour12 = rem(at.hour + 11, 12) + 1
    ampm = if at.hour >= 12, do: "PM", else: "AM"
    min = at.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{at.month}/#{at.day}/#{rem(at.year, 100)} #{hour12}:#{min} #{ampm}"
  end

  defp timestamp_line(_), do: timestamp_line(%{inserted_at: NaiveDateTime.local_now()})

  defp item_lines(item) do
    size = if item.size in [nil, ""], do: "", else: " #{item.size}"
    qty = item.quantity || 1
    unit = money(item.unit_price)
    line = money(item.line_total || Decimal.mult(item.unit_price || Decimal.new(0), qty))
    name = "#{item.name}#{size}"

    [
      EscPos.bold_on(),
      EscPos.columns(name, line),
      EscPos.bold_off(),
      EscPos.text_line("  #{qty} x #{unit}"),
      EscPos.feed(1)
    ]
  end

  defp wifi_block(%{wifi_ssid: ssid, wifi_password: password} = conf)
       when is_binary(ssid) and ssid != "" and is_binary(password) and password != "" do
    [
      EscPos.bold_on(),
      EscPos.text_line(conf.wifi_title),
      EscPos.feed(1),
      EscPos.text_line("Today's Network: #{ssid}"),
      EscPos.text_line("Today's Access Code: #{password}"),
      EscPos.bold_off(),
      EscPos.feed(1),
      EscPos.text_line("*#{conf.wifi_note}"),
      EscPos.text_line(conf.wifi_thanks),
      EscPos.feed(1),
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
