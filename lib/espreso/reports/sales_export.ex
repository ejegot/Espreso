defmodule Espreso.Reports.SalesExport do
  @moduledoc """
  Builds the Owner/Manager sales Excel workbook from paid order rows.

  Read-only transformation — does not change settlement, loyalty, or attribution.
  """

  alias Elixlsx.{Sheet, Workbook}
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.{Order, OrderItem}
  alias Espreso.Shifts.ShopSessionAdjustment

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

  @settlement_headers [
    "Date From",
    "Date To",
    "Gross Paid Sales",
    "Post-close Sales Corrections",
    "Net Settled Sales"
  ]

  @adjustment_headers [
    "Adjustment Date",
    "Shop Session",
    "Correction",
    "Original Receipt",
    "Original Payment",
    "Sales Impact",
    "Drawer Cash Impact",
    "Reason",
    "Recorded By"
  ]

  @doc false
  def sales_headers, do: @sales_headers

  @doc false
  def items_headers, do: @items_headers

  @doc false
  def settlement_headers, do: @settlement_headers

  @doc false
  def adjustment_headers, do: @adjustment_headers

  @doc """
  Builds an `.xlsx` binary for the given paid orders and inclusive shop dates.

  Returns `{:ok, {filename, binary}}`.
  """
  def build(orders, %Date{} = from_date, %Date{} = to_date) when is_list(orders) do
    build(orders, [], from_date, to_date)
  end

  def build(_, _, _), do: {:error, :invalid_orders}

  def build(orders, adjustments, %Date{} = from_date, %Date{} = to_date)
      when is_list(orders) and is_list(adjustments) do
    workbook = %Workbook{
      sheets: [
        sales_sheet(orders),
        items_sheet(orders),
        settlement_sheet(orders, adjustments, from_date, to_date),
        adjustments_sheet(adjustments)
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

  def build(_, _, _, _), do: {:error, :invalid_orders}

  defp sales_sheet(orders) do
    rows =
      Enum.map(orders, fn %Order{} = order ->
        [
          order_shop_date_string(order),
          settled_at_string(order.settled_at),
          order.number || "",
          source_label(order.source),
          payment_method_label(order.payment_method),
          payment_intent_label(order.payment_intent),
          Orders.split_payment_label(order) || Orders.paid_via_label(order.paid_via),
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
        paid_via = Orders.split_payment_label(order) || Orders.paid_via_label(order.paid_via)
        shop_date = order_shop_date_string(order)

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

  defp settlement_sheet(orders, adjustments, from_date, to_date) do
    gross_paid_total =
      Enum.reduce(orders, Decimal.new("0"), fn order, total ->
        Decimal.add(total, decimal(order.total))
      end)

    adjustments_total = adjustment_total(adjustments)

    rows = [
      [
        Date.to_iso8601(from_date),
        Date.to_iso8601(to_date),
        money(gross_paid_total),
        money(adjustments_total),
        money(Decimal.add(gross_paid_total, adjustments_total))
      ]
    ]

    %Sheet{name: "Settlement", rows: [@settlement_headers | rows]}
  end

  defp adjustments_sheet(adjustments) do
    rows =
      Enum.map(adjustments, fn %ShopSessionAdjustment{} = adjustment ->
        [
          adjustment_date(adjustment),
          adjustment.shop_session_id,
          adjustment_label(adjustment.kind),
          (adjustment.original_order && adjustment.original_order.number) || "",
          adjustment_payment_label(adjustment),
          money(adjustment.sales_impact),
          money(adjustment.drawer_impact),
          adjustment.reason || "",
          (adjustment.recorded_by_user && adjustment.recorded_by_user.name) || ""
        ]
      end)

    %Sheet{name: "Adjustments", rows: [@adjustment_headers | rows]}
  end

  defp adjustment_date(%ShopSessionAdjustment{shop_session: %{shop_date: %Date{} = date}}),
    do: Date.to_iso8601(date)

  defp adjustment_date(_), do: ""

  defp adjustment_label("refund"), do: "Refund"
  defp adjustment_label("duplicate_void"), do: "Duplicate void"
  defp adjustment_label(_), do: "Correction"

  defp adjustment_payment_label(%{
         payment_method: "split",
         payment_breakdown: breakdown
       }) do
    breakdown
    |> Map.keys()
    |> Enum.map(&Orders.paid_via_label/1)
    |> Enum.sort()
    |> Enum.join(" + ")
  end

  defp adjustment_payment_label(%{payment_method: method}), do: Orders.paid_via_label(method)

  defp adjustment_total(adjustments) do
    Enum.reduce(adjustments, Decimal.new("0"), fn adjustment, total ->
      Decimal.add(total, adjustment.sales_impact || Decimal.new("0"))
    end)
    |> Decimal.round(2)
  end

  defp order_shop_date_string(%Order{shop_session: %{shop_date: %Date{} = date}}),
    do: Date.to_iso8601(date)

  defp order_shop_date_string(%Order{settled_at: settled_at}), do: shop_date_string(settled_at)

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

  defp decimal(%Decimal{} = amount), do: amount
  defp decimal(_), do: Decimal.new("0")

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
