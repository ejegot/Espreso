defmodule Espreso.Reports.SalesExportTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias Espreso.Reports.SalesExport
  alias Espreso.Shifts.ShopSessionAdjustment

  import Ecto.Query

  setup do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Sheet Barista",
        email: "sheet.barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{barista: barista}
  end

  test "empty orders produce workbook with Sales and Items headers only" do
    assert {:ok, {filename, binary}} =
             SalesExport.build([], ~D[2026-09-01], ~D[2026-09-02])

    assert filename == "elilai-sales-2026-09-01-2026-09-02.xlsx"
    assert is_binary(binary)
    assert String.starts_with?(binary, "PK")

    assert SalesExport.sales_headers() == [
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

    assert SalesExport.items_headers() == [
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

    assert SalesExport.settlement_headers() == [
             "Date From",
             "Date To",
             "Gross Paid Sales",
             "Post-close Sales Corrections",
             "Net Settled Sales"
           ]

    assert SalesExport.adjustment_headers() == [
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
  end

  test "paid order and line items appear with separate payment fields", %{barista: barista} do
    order =
      create_paid!(barista,
        settled_at: ~U[2026-09-10 02:30:00Z],
        paid_via: "gcash",
        payment_intent: "gcash",
        price: "169"
      )

    assert {:ok, {_filename, binary}} =
             SalesExport.build([order], ~D[2026-09-10], ~D[2026-09-10])

    assert String.starts_with?(binary, "PK")

    # Spot-check human labels via builder helpers / order data contract
    assert Orders.paid_via_label("gcash") == "GCash"
    assert order.payment_method == "counter"
    assert order.payment_intent == "gcash"
    assert order.paid_via == "gcash"
    assert order.settlement_source == "pos"
    assert order.source == "pos"
    assert Enum.any?(order.items, &(&1.name == "Espresso"))
    assert Menu.format_price(order.total) =~ "₱"
  end

  test "sales workbook includes dated adjustment rows and net settlement totals", %{
    barista: barista
  } do
    order =
      create_paid!(barista,
        settled_at: ~U[2026-09-10 02:30:00Z],
        paid_via: "cash",
        price: "100"
      )

    session_date = ~D[2026-09-11]

    adjustment = %ShopSessionAdjustment{
      kind: "refund",
      reason: "Cash returned",
      payment_method: "cash",
      sales_impact: Decimal.new("-100"),
      drawer_impact: Decimal.new("-25"),
      shop_session_id: 42,
      shop_session: %Espreso.Shifts.ShopDayOpen{id: 42, shop_date: session_date},
      original_order: order,
      recorded_by_user: barista
    }

    assert {:ok, {_filename, binary}} =
             SalesExport.build([order], [adjustment], ~D[2026-09-10], session_date)

    assert String.starts_with?(binary, "PK")
    assert {:ok, files} = :zip.unzip(binary, [:memory])
    assert cell_value(files, "xl/worksheets/sheet3.xml", "C2") == "₱200"
    assert cell_value(files, "xl/worksheets/sheet3.xml", "D2") == "−₱100"
    assert cell_value(files, "xl/worksheets/sheet3.xml", "E2") == "₱100"

    assert cell_value(files, "xl/worksheets/sheet4.xml", "A2") ==
             Date.to_iso8601(session_date)

    assert cell_value(files, "xl/worksheets/sheet4.xml", "B2") == "42"
    assert cell_value(files, "xl/worksheets/sheet4.xml", "D2") == order.number
    assert cell_value(files, "xl/worksheets/sheet4.xml", "F2") == "−₱100"
    assert cell_value(files, "xl/worksheets/sheet4.xml", "G2") == "−₱25"
    assert cell_value(files, "xl/worksheets/sheet4.xml", "H2") == "Cash returned"
  end

  defp cell_value(files, sheet_path, cell_reference) do
    sheet_xml = unzip_entry!(files, sheet_path)

    [_, attributes, content] =
      Regex.run(
        ~r/<c r="#{cell_reference}"([^>]*)>(.*?)<\/c>/s,
        sheet_xml
      )

    [_, value] = Regex.run(~r/<v>(.*?)<\/v>/s, content)

    if attributes =~ ~r/\bt="s"/ do
      shared_strings_xml = unzip_entry!(files, "xl/sharedStrings.xml")

      shared_strings =
        Regex.scan(~r/<si>(.*?)<\/si>/s, shared_strings_xml, capture: :all_but_first)
        |> Enum.map(fn [item] ->
          [_, string] = Regex.run(~r/<t(?:\s[^>]*)?>(.*?)<\/t>/s, item)
          string
        end)

      Enum.at(shared_strings, String.to_integer(value))
    else
      value
    end
  end

  defp unzip_entry!(files, name) do
    {_name, content} = Enum.find(files, fn {entry_name, _} -> to_string(entry_name) == name end)
    IO.iodata_to_binary(content)
  end

  defp create_paid!(user, opts) do
    settled_at = Keyword.fetch!(opts, :settled_at)
    price = Keyword.get(opts, :price, "100")
    paid_via = Keyword.get(opts, :paid_via, "cash")
    payment_intent = Keyword.get(opts, :payment_intent)

    attrs = %{
      customer_name: "Sheet Guest",
      fulfillment: :pickup,
      payment_method: :counter,
      payment_status: :paid,
      paid_via: paid_via,
      source: :pos,
      settlement_source: :pos,
      settled_by_user_id: user.id
    }

    attrs =
      if payment_intent,
        do: Map.put(attrs, :payment_intent, payment_intent),
        else: attrs

    line = pos_line!(price, qty: 2)

    {:ok, order} = Orders.create_order([line], attrs)

    {1, _} =
      Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [settled_at: settled_at])

    Orders.get_transaction(order.id)
  end

  defp pos_line!(amount, opts) do
    qty = Keyword.get(opts, :qty, 1)

    category =
      %Espreso.Menu.Category{}
      |> Espreso.Menu.Category.changeset(%{
        name: "SheetCat-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    product =
      %Espreso.Menu.Product{}
      |> Espreso.Menu.Product.changeset(%{
        name: "Espresso",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    price =
      %Espreso.Menu.ProductPrice{}
      |> Espreso.Menu.ProductPrice.changeset(%{
        product_id: product.id,
        size: "12oz",
        price: Decimal.new(amount)
      })
      |> Repo.insert!()

    %{
      product_id: product.id,
      price_id: price.id,
      name: product.name,
      size: price.size,
      quantity: qty,
      price: price.price
    }
  end
end
