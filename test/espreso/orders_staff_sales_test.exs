defmodule Espreso.OrdersStaffSalesTest do
  use Espreso.DataCase, async: true

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias Espreso.StaffShifts.StaffShift

  setup do
    {:ok, employee_a} =
      Accounts.register_user(%{
        name: "Employee A",
        email: "staff.sales.a@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, employee_b} =
      Accounts.register_user(%{
        name: "Employee B",
        email: "staff.sales.b@test.local",
        password: "password123",
        role: "barista"
      })

    %{employee_a: employee_a, employee_b: employee_b}
  end

  describe "sales_summary_for_staff_shift/1" do
    test "includes paid POS order settled by employee during open shift", %{
      employee_a: employee_a
    } do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)
      order = create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 02:00:00Z], price: "150")

      summary = Orders.sales_summary_for_staff_shift(shift)

      assert summary.order_count == 1
      assert Decimal.equal?(summary.total, order.total)
      assert Decimal.equal?(summary.total, Decimal.new("150"))
    end

    test "includes both cash and GCash paid POS orders", %{employee_a: employee_a} do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)

      create_paid_pos!(employee_a,
        settled_at: ~U[2026-09-10 02:00:00Z],
        paid_via: "cash",
        price: "100"
      )

      create_paid_pos!(employee_a,
        settled_at: ~U[2026-09-10 03:00:00Z],
        paid_via: "gcash",
        price: "200"
      )

      summary = Orders.sales_summary_for_staff_shift(shift)

      assert summary.order_count == 2
      assert Decimal.equal?(summary.total, Decimal.new("300"))
    end

    test "unpaid POS settled by another employee credits settler only", %{
      employee_a: employee_a,
      employee_b: employee_b
    } do
      started = ~U[2026-09-10 01:00:00Z]
      shift_a = insert_shift!(employee_a, started)
      shift_b = insert_shift!(employee_b, started)

      {:ok, unpaid} =
        Orders.create_order(pos_lines("120"), %{
          customer_name: "Walk-in",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :unpaid,
          source: :pos
        })

      assert unpaid.source == "pos"
      assert unpaid.payment_status == "unpaid"
      assert is_nil(unpaid.settled_by_user_id)

      assert {:ok, paid} =
               Orders.mark_paid(unpaid,
                 paid_via: "cash",
                 settled_by_user_id: employee_b.id,
                 settlement_source: "staff_orders"
               )

      assert paid.source == "pos"
      assert paid.settlement_source == "staff_orders"
      assert paid.settled_by_user_id == employee_b.id

      settled_at = ~U[2026-09-10 02:30:00Z]
      set_settled_at!(paid, settled_at)

      assert Orders.sales_summary_for_staff_shift(shift_b) == %{
               order_count: 1,
               total: Decimal.new("120")
             }

      assert Orders.sales_summary_for_staff_shift(shift_a) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "excludes settlement before Time In", %{employee_a: employee_a} do
      started = ~U[2026-09-10 09:00:00Z]
      shift = insert_shift!(employee_a, started, ~U[2026-09-10 17:00:00Z])

      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 08:59:59Z], price: "100")

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "includes settlement exactly at Time In", %{employee_a: employee_a} do
      started = ~U[2026-09-10 09:00:00Z]
      shift = insert_shift!(employee_a, started, ~U[2026-09-10 17:00:00Z])

      create_paid_pos!(employee_a, settled_at: started, price: "100")

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 1,
               total: Decimal.new("100")
             }
    end

    test "excludes settlement after Time Out", %{employee_a: employee_a} do
      started = ~U[2026-09-10 09:00:00Z]
      ended = ~U[2026-09-10 17:00:00Z]
      shift = insert_shift!(employee_a, started, ended)

      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 17:00:01Z], price: "100")

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "excludes settlement exactly at Time Out", %{employee_a: employee_a} do
      started = ~U[2026-09-10 09:00:00Z]
      ended = ~U[2026-09-10 17:00:00Z]
      shift = insert_shift!(employee_a, started, ended)

      create_paid_pos!(employee_a, settled_at: ended, price: "100")

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "open shift includes later qualifying settlement", %{employee_a: employee_a} do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)

      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 13:00:00Z], price: "250")

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 1,
               total: Decimal.new("250")
             }
    end

    test "excludes customer-originated paid orders", %{employee_a: employee_a} do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)

      {:ok, unpaid} =
        Orders.create_order(pos_lines("90"), %{
          customer_name: "QR Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :unpaid,
          source: :customer
        })

      assert unpaid.source == "customer"

      assert {:ok, paid} =
               Orders.mark_paid(unpaid,
                 paid_via: "cash",
                 settled_by_user_id: employee_a.id,
                 settlement_source: "staff_orders"
               )

      set_settled_at!(paid, ~U[2026-09-10 02:00:00Z])

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "excludes unpaid orders", %{employee_a: employee_a} do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)

      {:ok, unpaid} =
        Orders.create_order(pos_lines("80"), %{
          customer_name: "Walk-in",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :unpaid,
          source: :pos
        })

      assert unpaid.payment_status == "unpaid"

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "excludes cancelled unpaid orders", %{employee_a: employee_a} do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)

      {:ok, unpaid} =
        Orders.create_order(pos_lines("70"), %{
          customer_name: "Walk-in",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :unpaid,
          source: :pos
        })

      assert {:ok, cancelled} = Orders.cancel_order(unpaid)
      assert cancelled.status == "cancelled"
      assert cancelled.payment_status == "unpaid"

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "does not include another employee's settlements", %{
      employee_a: employee_a,
      employee_b: employee_b
    } do
      started = ~U[2026-09-10 01:00:00Z]
      shift_a = insert_shift!(employee_a, started)
      _shift_b = insert_shift!(employee_b, started)

      create_paid_pos!(employee_b, settled_at: ~U[2026-09-10 02:00:00Z], price: "500")

      assert Orders.sales_summary_for_staff_shift(shift_a) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "maps sales to the correct shift for multiple shifts same day", %{
      employee_a: employee_a
    } do
      morning = insert_shift!(employee_a, ~U[2026-09-10 01:00:00Z], ~U[2026-09-10 04:00:00Z])
      afternoon = insert_shift!(employee_a, ~U[2026-09-10 05:00:00Z], ~U[2026-09-10 09:00:00Z])

      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 02:00:00Z], price: "100")
      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 06:00:00Z], price: "200")

      assert Orders.sales_summary_for_staff_shift(morning) == %{
               order_count: 1,
               total: Decimal.new("100")
             }

      assert Orders.sales_summary_for_staff_shift(afternoon) == %{
               order_count: 1,
               total: Decimal.new("200")
             }
    end

    test "auto-close handoff attributes sale at boundary to new shift only", %{
      employee_a: employee_a
    } do
      handoff = ~U[2026-09-10 04:00:00Z]
      old_shift = insert_shift!(employee_a, ~U[2026-09-10 01:00:00Z], handoff, "auto_close")
      new_shift = insert_shift!(employee_a, handoff)

      create_paid_pos!(employee_a, settled_at: handoff, price: "175")

      assert Orders.sales_summary_for_staff_shift(old_shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }

      assert Orders.sales_summary_for_staff_shift(new_shift) == %{
               order_count: 1,
               total: Decimal.new("175")
             }
    end

    test "excludes orders settled by a different employee", %{
      employee_a: employee_a,
      employee_b: employee_b
    } do
      started = ~U[2026-09-10 01:00:00Z]
      shift_a = insert_shift!(employee_a, started)

      create_paid_pos!(employee_b, settled_at: ~U[2026-09-10 02:00:00Z], price: "100")

      assert Orders.sales_summary_for_staff_shift(shift_a) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "excludes paid orders with nil settler", %{employee_a: employee_a} do
      started = ~U[2026-09-10 01:00:00Z]
      shift = insert_shift!(employee_a, started)

      {:ok, unpaid} =
        Orders.create_order(pos_lines("110"), %{
          customer_name: "Walk-in",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :unpaid,
          source: :pos
        })

      assert {:ok, paid} = Orders.mark_paid(unpaid, paid_via: "cash")
      assert is_nil(paid.settled_by_user_id)

      set_settled_at!(paid, ~U[2026-09-10 02:00:00Z])

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 0,
               total: Decimal.new("0")
             }
    end

    test "aggregates multiple qualifying orders and ignores non-qualifying", %{
      employee_a: employee_a,
      employee_b: employee_b
    } do
      started = ~U[2026-09-10 01:00:00Z]
      ended = ~U[2026-09-10 10:00:00Z]
      shift = insert_shift!(employee_a, started, ended)

      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 02:00:00Z], price: "100")
      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 03:00:00Z], price: "50")
      # outside window
      create_paid_pos!(employee_a, settled_at: ~U[2026-09-10 11:00:00Z], price: "999")
      # other employee
      create_paid_pos!(employee_b, settled_at: ~U[2026-09-10 04:00:00Z], price: "888")

      {:ok, customer} =
        Orders.create_order(pos_lines("777"), %{
          customer_name: "Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :unpaid,
          source: :customer
        })

      {:ok, customer_paid} =
        Orders.mark_paid(customer,
          paid_via: "cash",
          settled_by_user_id: employee_a.id,
          settlement_source: "staff_orders"
        )

      set_settled_at!(customer_paid, ~U[2026-09-10 05:00:00Z])

      assert Orders.sales_summary_for_staff_shift(shift) == %{
               order_count: 2,
               total: Decimal.new("150")
             }
    end
  end

  defp pos_lines(price) do
    [insert_pos_line!(price)]
  end

  defp insert_pos_line!(amount) do
    category =
      %Espreso.Menu.Category{}
      |> Espreso.Menu.Category.changeset(%{
        name: "StaffSales-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    product =
      %Espreso.Menu.Product{}
      |> Espreso.Menu.Product.changeset(%{
        name: "Espresso-#{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    price =
      %Espreso.Menu.ProductPrice{}
      |> Espreso.Menu.ProductPrice.changeset(%{
        product_id: product.id,
        size: nil,
        price: Decimal.new(amount)
      })
      |> Repo.insert!()

    %{
      product_id: product.id,
      price_id: price.id,
      name: product.name,
      size: price.size,
      quantity: 1,
      price: price.price
    }
  end

  defp insert_shift!(user, started_at, ended_at \\ nil, end_reason \\ "logout") do
    {:ok, shift} =
      %StaffShift{}
      |> StaffShift.open_changeset(%{user_id: user.id, started_at: started_at})
      |> Repo.insert()

    if is_nil(ended_at) do
      shift
    else
      shift
      |> StaffShift.close_changeset(%{ended_at: ended_at, end_reason: end_reason})
      |> Repo.update!()
    end
  end

  defp create_paid_pos!(user, opts) do
    settled_at = Keyword.fetch!(opts, :settled_at)
    paid_via = Keyword.get(opts, :paid_via, "cash")
    price = Keyword.get(opts, :price, "100")
    settlement_source = Keyword.get(opts, :settlement_source, "pos")

    {:ok, order} =
      Orders.create_order(pos_lines(price), %{
        customer_name: "Walk-in",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: paid_via,
        source: :pos,
        settled_by_user_id: user.id,
        settlement_source: settlement_source
      })

    set_settled_at!(order, settled_at)
  end

  defp set_settled_at!(%Order{id: id}, %DateTime{} = settled_at) do
    Repo.update_all(from(o in Order, where: o.id == ^id), set: [settled_at: settled_at])
    Repo.get!(Order, id)
  end
end
