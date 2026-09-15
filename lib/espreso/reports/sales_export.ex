defmodule Espreso.Reports.SalesExport do
  @moduledoc """
  Builds the Owner/Manager sales Excel workbook from paid order rows.

  Read-only transformation — does not change settlement, loyalty, or attribution.
  """

  alias Elixlsx.{Sheet, Workbook}
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.{Order, OrderItem}

  @shop_utc_offset_seconds 8 * 60 * 60

  @sales_headers [
    "Shop Date",
    "Settled At",
    "Order #",
    "Source",
    "Payment Method",
    "Payment Intent",
    "Paid Via",
    "Settlement Source",
    "Total",
    "Loyalty Free",
    "Settled By",
    "Customer Name",
    "Fulfillment",
    "Order Status"
  ]

  @items_headers [
    "Shop Date",
    "Order #",
    "Product",
    "Size",
    "Qty",
    "Unit Price",
    "Line Total",
    "Settled By",
    "Paid Via"
  ]

  @doc false
  def sales_headers, do: @sales_headers

  @doc false
  def items_headers, do: @items_headers

  @doc """
  Builds an `.xlsx` binary for the given paid orders and inclusive shop dates.

  Returns `{:ok, {filename, binary}}`.
  """
  def build(orders, %Date{} = from_date, %Date{} = to_date) when is_list(orders) do
    workbook = %Workbook{
      sheets: [
        sales_sheet(orders),
        items_sheet(orders)
      ]
    }

    filename = "elilai-sales-#{Date.to_iso8601(from_date)}-#{Date.to_iso8601(to_date)}.xlsx"

    case Elixlsx.write_to_memory(workbook, filename) do
      {:ok, {_name, binary}} when is_binary(binary) ->
        {:ok, {filename, binary}}

      {:ok, {name, binary}} when is_list(name) and is_binary(binary) ->
        {:ok, {List.to_string(name), binary}}

      other ->
        {:error, {:xlsx_write_failed, other}}
    end
  end

  def build(_, _, _), do: {:error, :invalid_orders}

  defp sales_sheet(orders) do
    rows =
      Enum.map(orders, fn %Order{} = order ->
        [
          shop_date_string(order.settled_at),
          settled_at_string(order.settled_at),
          order.number || "",
          source_label(order.source),
          payment_method_label(order.payment_method),
          payment_intent_label(order.payment_intent),
          Orders.paid_via_label(order.paid_via),
          settlement_source_label(order.settlement_source),
          money(order.total),
          loyalty_free_money(order.loyalty_free_amount_centavos),
          settled_by_name(order),
          order.customer_name || "",
          fulfillment_label(order.fulfillment),
          status_label(order.status)
        ]
      end)

    %Sheet{name: "Sales", rows: [@sales_headers | rows]}
  end

  defp items_sheet(orders) do
    rows =
      orders
      |> Enum.flat_map(fn %Order{} = order ->
        settler = settled_by_name(order)
        paid_via = Orders.paid_via_label(order.paid_via)
        shop_date = shop_date_string(order.settled_at)

        (order.items || [])
        |> Enum.sort_by(& &1.id)
        |> Enum.map(fn %OrderItem{} = item ->
          [
            shop_date,
            order.number || "",
            item.name || "",
            item.size || "",
            item.quantity || 0,
            money(item.unit_price),
            money(item.line_total),
            settler,
            paid_via
          ]
        end)
      end)

    %Sheet{name: "Items", rows: [@items_headers | rows]}
  end

  defp shop_date_string(%DateTime{} = settled_at) do
    settled_at
    |> manila_datetime()
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp shop_date_string(_), do: ""

  defp settled_at_string(%DateTime{} = settled_at) do
    settled_at
    |> manila_datetime()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp settled_at_string(_), do: ""

  defp manila_datetime(%DateTime{} = at),
    do: DateTime.add(at, @shop_utc_offset_seconds, :second)

  defp money(nil), do: Menu.format_price(Decimal.new("0"))
  defp money(%Decimal{} = amount), do: Menu.format_price(amount)
  defp money(amount) when is_integer(amount), do: Menu.format_price(Decimal.new(amount))
  defp money(amount) when is_binary(amount), do: Menu.format_price(Decimal.new(amount))
  defp money(_), do: Menu.format_price(Decimal.new("0"))

  defp loyalty_free_money(centavos) when is_integer(centavos) and centavos > 0 do
    centavos
    |> Decimal.new()
    |> Decimal.div(Decimal.new(100))
    |> Menu.format_price()
  end

  defp loyalty_free_money(_), do: Menu.format_price(Decimal.new("0"))

  defp settled_by_name(%Order{settled_by_user: %{name: name}}) when is_binary(name), do: name
  defp settled_by_name(%Order{settlement_time_estimated: true}), do: "Legacy record"
  defp settled_by_name(_), do: "Not recorded"

  defp source_label("pos"), do: "POS"
  defp source_label("customer"), do: "Customer"
  defp source_label(_), do: "—"

  defp payment_method_label("counter"), do: "Counter"
  defp payment_method_label("online"), do: "Online"
  defp payment_method_label(_), do: "—"

  defp payment_intent_label("cash"), do: "Cash"
  defp payment_intent_label("gcash"), do: "GCash"
  defp payment_intent_label("maya"), do: "Maya"
  defp payment_intent_label(_), do: "—"

  defp settlement_source_label("pos"), do: "POS"
  defp settlement_source_label("staff_orders"), do: "Orders board"
  defp settlement_source_label("api"), do: "Staff API"
  defp settlement_source_label("paymongo"), do: "PayMongo"
  defp settlement_source_label("legacy"), do: "Legacy"
  defp settlement_source_label("manual"), do: "Manual"
  defp settlement_source_label(_), do: "—"

  defp fulfillment_label("dine_in"), do: "Dine-in"
  defp fulfillment_label("pickup"), do: "Takeout"
  defp fulfillment_label(_), do: "—"

  defp status_label(status) when is_binary(status), do: String.capitalize(status)
  defp status_label(_), do: "—"
end
