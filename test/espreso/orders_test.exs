defmodule Espreso.OrdersTest do
  use Espreso.DataCase, async: true

  import Ecto.Query

  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo

  test "create_order assigns CS number and stores lines" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")},
      %{name: "Americano", size: "12oz", quantity: 2, price: Decimal.new("120")}
    ]

    assert {:ok, order} =
             Orders.create_order(lines, %{
               customer_name: "Juan",
               fulfillment: :dine_in,
               table_number: "7",
               notes: "less ice",
               payment_method: :counter
             })

    assert order.number =~ Orders.order_number_pattern()
    refute order.number =~ ~r/^CS-0+\d+$/
    assert order.customer_name == "Juan"
    assert order.fulfillment == "dine_in"
    assert order.table_number == "7"
    assert order.payment_method == "counter"
    assert order.payment_status == "unpaid"
    assert order.status == "received"
    assert order.source == "customer"
    assert Decimal.equal?(order.total, Decimal.new("315"))
    assert length(order.items) == 2
  end

  test "list_orders_by_numbers returns matching orders and ignores invalid input" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    assert {:ok, first} =
             Orders.create_order(lines, %{
               customer_name: "One",
               fulfillment: :pickup,
               payment_method: :counter
             })

    assert {:ok, second} =
             Orders.create_order(lines, %{
               customer_name: "Two",
               fulfillment: :pickup,
               payment_method: :counter
             })

    orders =
      Orders.list_orders_by_numbers([
        second.number,
        "not-valid",
        first.number,
        first.number,
        "CS-222222"
      ])

    assert MapSet.new(Enum.map(orders, & &1.number)) ==
             MapSet.new([first.number, second.number])

    assert length(orders) == 2
    assert Orders.list_orders_by_numbers([]) == []
    assert Orders.list_orders_by_numbers(nil) == []
  end

  test "create_order assigns unique random numbers" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    numbers =
      for i <- 1..25 do
        {:ok, order} =
          Orders.create_order(lines, %{
            customer_name: "Guest #{i}",
            fulfillment: :pickup,
            payment_method: :counter
          })

        order.number
      end

    assert length(numbers) == length(Enum.uniq(numbers))

    Enum.each(numbers, fn number ->
      assert number =~ Orders.order_number_pattern()
    end)
  end

  test "get_order_by_number finds order by public number" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Juan",
        fulfillment: :pickup,
        payment_method: :counter
      })

    found = Orders.get_order_by_number!(order.number)
    assert found.id == order.id
    assert found.number == order.number
  end

  test "create_order accepts source pos" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    assert {:ok, order} =
             Orders.create_order(lines, %{
               customer_name: "Walk-in",
               fulfillment: :pickup,
               payment_method: :counter,
               source: :pos
             })

    assert order.source == "pos"
    assert order.fulfillment == "pickup"
    assert order.payment_status == "unpaid"
    assert order.status == "received"
  end

  test "create_order requires table for dine-in" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    assert {:error, changeset} =
             Orders.create_order(lines, %{
               customer_name: "Juan",
               fulfillment: :dine_in,
               table_number: "",
               payment_method: :counter
             })

    assert %{table_number: _} = errors_on(changeset)
  end

  test "update_status and mark_paid" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Ana",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert preparing.status == "preparing"

    assert {:ok, paid} = Orders.mark_paid(preparing)
    assert paid.payment_status == "paid"
    assert paid.payment_method == "counter"

    assert [%{number: number}] = Orders.list_active_orders()
    assert number == order.number
  end

  test "mark_paid from received advances to preparing" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Auto Prep",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert order.status == "received"
    assert {:ok, paid} = Orders.mark_paid(order, paid_via: "maya")
    assert paid.payment_status == "paid"
    assert paid.status == "preparing"
    assert paid.paid_via == "maya"
  end

  test "mark_paid is idempotent when already paid" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Idempotent",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:ok, paid} = Orders.mark_paid(order)
    assert paid.payment_status == "paid"
    assert paid.payment_method == "counter"

    assert {:ok, again} = Orders.mark_paid(paid)
    assert again.id == paid.id
    assert again.payment_status == "paid"
    assert again.payment_method == "counter"
  end

  test "mark_paid rejects cancelled orders" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Cancelled Pay",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:ok, cancelled} = Orders.cancel_order(order)
    assert cancelled.status == "cancelled"
    assert {:error, :cancelled} = Orders.mark_paid(cancelled)
  end

  test "online unpaid cannot be manually marked paid; PayMongo helper can" do
    lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Online Manual Pay",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_esp87_manual")
    assert order.payment_status == "unpaid"

    assert {:error, :online_payment_required} = Orders.mark_paid(order)
    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.payment_status == "unpaid"

    assert {:ok, paid} = Orders.mark_paid_from_paymongo(order.number)
    assert paid.payment_status == "paid"
    assert paid.payment_method == "online"

    assert {:ok, again} = Orders.mark_paid(paid)
    assert again.payment_status == "paid"
  end

  test "online unpaid can prepare but not become ready or completed" do
    lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Online Fulfill Gate",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_esp87_fulfill")

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert preparing.status == "preparing"
    assert preparing.payment_status == "unpaid"

    assert {:error, :payment_required} = Orders.update_status(preparing, "ready")
    still_preparing = Orders.get_order_by_number!(order.number)
    assert still_preparing.status == "preparing"
    assert still_preparing.payment_status == "unpaid"

    # Defense-in-depth: legacy ready + unpaid online cannot complete.
    {:ok, legacy_ready} =
      still_preparing
      |> Ecto.Changeset.change(%{status: "ready"})
      |> Espreso.Repo.update()

    assert {:error, :payment_required} = Orders.complete_order(legacy_ready)
    assert Orders.get_order_by_number!(order.number).status == "ready"
    assert Orders.get_order_by_number!(order.number).payment_status == "unpaid"

    assert {:ok, paid} = Orders.mark_paid_from_paymongo_session("cs_esp87_fulfill")
    assert paid.payment_status == "paid"

    assert {:ok, ready} = Orders.update_status(paid, "ready")
    assert ready.status == "ready"
    assert {:ok, completed} = Orders.complete_order(ready)
    assert completed.status == "completed"
    assert completed.payment_status == "paid"
  end

  test "abandoned online order stays unpaid and cannot be manually marked paid" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Abandon Then Pay",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_esp87_abandon")
    assert {:ok, abandoned} = Orders.abandon_online_payment(order)
    assert abandoned.status == "cancelled"
    assert abandoned.payment_status == "unpaid"

    assert {:error, :cancelled} = Orders.mark_paid(abandoned)
    assert {:error, :cancelled} = Orders.mark_paid_from_paymongo(abandoned.number)
  end

  test "record_paymongo_reconciliation is idempotent on checkout session id" do
    lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Recon Idempotent",
        fulfillment: :pickup,
        payment_method: :online
      })

    attrs = %{
      order_id: order.id,
      order_number: order.number,
      paymongo_checkout_session_id: "cs_recon_once",
      paymongo_payment_id: "pay_recon_1",
      paymongo_webhook_event_id: "evt_recon_1",
      amount_centavos: 10_000,
      currency: "PHP"
    }

    assert {:ok, first} = Orders.record_paymongo_reconciliation(attrs)
    assert {:ok, second} = Orders.record_paymongo_reconciliation(attrs)
    assert first.id == second.id

    assert Espreso.Repo.aggregate(Espreso.Orders.PaymentReconciliation, :count, :id) == 1
  end

  test "attach_paymongo_session enforces unique checkout session binding" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order1} =
      Orders.create_order(lines, %{
        customer_name: "Session One",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, order2} =
      Orders.create_order(lines, %{
        customer_name: "Session Two",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, order3} =
      Orders.create_order(lines, %{
        customer_name: "Session Three",
        fulfillment: :pickup,
        payment_method: :online
      })

    assert is_nil(order1.paymongo_checkout_session_id)
    assert is_nil(order2.paymongo_checkout_session_id)
    assert is_nil(order3.paymongo_checkout_session_id)

    assert {:ok, order1} = Orders.attach_paymongo_session(order1, "cs_A")
    assert order1.paymongo_checkout_session_id == "cs_A"

    assert {:error, changeset} = Orders.attach_paymongo_session(order2, "cs_A")
    assert %{paymongo_checkout_session_id: ["has already been taken"]} = errors_on(changeset)
    assert is_nil(Repo.get!(Order, order2.id).paymongo_checkout_session_id)
    assert Repo.get!(Order, order1.id).paymongo_checkout_session_id == "cs_A"

    assert {:ok, again} = Orders.attach_paymongo_session(order1, "cs_A")
    assert again.id == order1.id
    assert again.paymongo_checkout_session_id == "cs_A"

    assert {:ok, order2} = Orders.attach_paymongo_session(order2, "cs_B")
    assert order2.paymongo_checkout_session_id == "cs_B"
    assert Repo.get!(Order, order1.id).paymongo_checkout_session_id == "cs_A"
    assert is_nil(Repo.get!(Order, order3.id).paymongo_checkout_session_id)
  end

  test "cancel_order rejects unpaid orders with an attached PayMongo session" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, received} =
      Orders.create_order(lines, %{
        customer_name: "Online Rec",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, received} = Orders.attach_paymongo_session(received, "cs_cancel_rec")

    assert {:error, :checkout_in_progress} = Orders.cancel_order(received)
    received = Repo.get!(Order, received.id)
    assert received.status == "received"
    assert received.payment_status == "unpaid"
    assert received.paymongo_checkout_session_id == "cs_cancel_rec"

    {:ok, preparing} =
      Orders.create_order(lines, %{
        customer_name: "Online Prep",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, preparing} = Orders.update_status(preparing, "preparing")
    {:ok, preparing} = Orders.attach_paymongo_session(preparing, "cs_cancel_prep")

    assert {:error, :checkout_in_progress} = Orders.cancel_order(preparing)
    preparing = Repo.get!(Order, preparing.id)
    assert preparing.status == "preparing"
    assert preparing.payment_status == "unpaid"
    assert preparing.paymongo_checkout_session_id == "cs_cancel_prep"
  end

  test "abandon_online_payment cancels unpaid online orders with a session preserved" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Abandon Me",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_abandon_ok")

    assert {:ok, abandoned} = Orders.abandon_online_payment(order)
    assert abandoned.status == "cancelled"
    assert abandoned.payment_status == "unpaid"
    assert abandoned.paymongo_checkout_session_id == "cs_abandon_ok"

    abandoned = Repo.get!(Order, abandoned.id)
    assert abandoned.status == "cancelled"
    assert abandoned.payment_status == "unpaid"
    assert abandoned.paymongo_checkout_session_id == "cs_abandon_ok"
    assert {:error, :invalid_status} = Orders.cancel_order(abandoned)

    {:ok, still_open} =
      Orders.create_order(lines, %{
        customer_name: "Still Paying",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, still_open} = Orders.attach_paymongo_session(still_open, "cs_still_open")
    assert {:error, :checkout_in_progress} = Orders.cancel_order(still_open)
  end

  test "abandon_online_payment rejects paid, unbound, ready, and already cancelled orders" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, unbound} =
      Orders.create_order(lines, %{
        customer_name: "No Session",
        fulfillment: :pickup,
        payment_method: :online
      })

    assert {:error, :missing_checkout_session} = Orders.abandon_online_payment(unbound)

    {:ok, counter} =
      Orders.create_order(lines, %{
        customer_name: "Counter",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:error, :not_online} = Orders.abandon_online_payment(counter)

    {:ok, paid} =
      Orders.create_order(lines, %{
        customer_name: "Paid Online",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, paid} = Orders.attach_paymongo_session(paid, "cs_abandon_paid")
    assert {:ok, paid} = Orders.mark_paid_from_paymongo(paid.number)
    assert {:error, :paid} = Orders.abandon_online_payment(paid)

    {:ok, ready} =
      Orders.create_order(lines, %{
        customer_name: "Ready Online",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, ready} = Orders.attach_paymongo_session(ready, "cs_abandon_ready")
    {:ok, ready} = Orders.update_status(ready, "preparing")

    {:ok, ready} =
      ready
      |> Ecto.Changeset.change(%{status: "ready"})
      |> Espreso.Repo.update()

    assert {:error, :invalid_status} = Orders.abandon_online_payment(ready)

    {:ok, to_cancel} =
      Orders.create_order(lines, %{
        customer_name: "Already Gone",
        fulfillment: :pickup,
        payment_method: :online
      })

    {:ok, to_cancel} = Orders.attach_paymongo_session(to_cancel, "cs_abandon_done")
    {:ok, cancelled} = Orders.abandon_online_payment(to_cancel)
    assert {:error, :invalid_status} = Orders.abandon_online_payment(cancelled)
    assert {:error, :cancelled} = Orders.attach_paymongo_session(cancelled, "cs_new")
  end

  test "cancel_order still voids unpaid orders without a PayMongo session" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, counter} =
      Orders.create_order(lines, %{
        customer_name: "Counter Void",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, online} =
      Orders.create_order(lines, %{
        customer_name: "Online Unbound",
        fulfillment: :pickup,
        payment_method: :online
      })

    assert is_nil(counter.paymongo_checkout_session_id)
    assert is_nil(online.paymongo_checkout_session_id)

    assert {:ok, cancelled_counter} = Orders.cancel_order(counter)
    assert cancelled_counter.status == "cancelled"

    assert {:ok, cancelled_online} = Orders.cancel_order(online)
    assert cancelled_online.status == "cancelled"
  end

  test "attach_paymongo_session rejects cancelled orders" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Attach Cancelled",
        fulfillment: :pickup,
        payment_method: :online
      })

    assert {:ok, cancelled} = Orders.cancel_order(order)
    assert cancelled.status == "cancelled"
    assert is_nil(cancelled.paymongo_checkout_session_id)

    assert {:error, :cancelled} = Orders.attach_paymongo_session(cancelled, "cs_after_cancel")
    assert is_nil(Repo.get!(Order, cancelled.id).paymongo_checkout_session_id)
  end

  test "create_order allows paid only for counter payment" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    assert {:ok, paid} =
             Orders.create_order(lines, %{
               customer_name: "Walk-in",
               fulfillment: :pickup,
               payment_method: :counter,
               payment_status: :paid,
               source: :pos
             })

    assert paid.payment_method == "counter"
    assert paid.payment_status == "paid"
    assert paid.source == "pos"
    assert paid.status == "preparing"

    assert {:ok, online} =
             Orders.create_order(lines, %{
               customer_name: "Online Attempt",
               fulfillment: :pickup,
               payment_method: :online,
               payment_status: :paid
             })

    assert online.payment_method == "online"
    assert online.payment_status == "unpaid"
  end

  test "create_order rejects unavailable products and creates nothing" do
    alias Espreso.Menu.{Category, Product, ProductPrice}
    alias Espreso.Repo

    category =
      %Category{}
      |> Category.changeset(%{name: "HOT"})
      |> Repo.insert!()

    available =
      %Product{}
      |> Product.changeset(%{name: "Latte", category_id: category.id, available: true})
      |> Repo.insert!()

    %ProductPrice{}
    |> ProductPrice.changeset(%{
      product_id: available.id,
      size: nil,
      price: Decimal.new("120")
    })
    |> Repo.insert!()

    unavailable =
      %Product{}
      |> Product.changeset(%{name: "Mocha", category_id: category.id, available: false})
      |> Repo.insert!()

    %ProductPrice{}
    |> ProductPrice.changeset(%{
      product_id: unavailable.id,
      size: nil,
      price: Decimal.new("140")
    })
    |> Repo.insert!()

    assert {:ok, order} =
             Orders.create_order(
               [
                 %{
                   product_id: available.id,
                   name: available.name,
                   size: nil,
                   quantity: 1,
                   price: Decimal.new("120")
                 }
               ],
               %{
                 customer_name: "Avail Ok",
                 fulfillment: :pickup,
                 payment_method: :counter
               }
             )

    assert order.status == "received"

    before_count = Repo.aggregate(Espreso.Orders.Order, :count, :id)
    before_items = Repo.aggregate(Espreso.Orders.OrderItem, :count, :id)

    assert {:error, {:unavailable, ["Mocha"]}} =
             Orders.create_order(
               [
                 %{
                   product_id: available.id,
                   name: available.name,
                   size: nil,
                   quantity: 1,
                   price: Decimal.new("120")
                 },
                 %{
                   product_id: unavailable.id,
                   name: unavailable.name,
                   size: nil,
                   quantity: 1,
                   price: Decimal.new("140")
                 }
               ],
               %{
                 customer_name: "Partial Fail",
                 fulfillment: :pickup,
                 payment_method: :counter
               }
             )

    assert Repo.aggregate(Espreso.Orders.Order, :count, :id) == before_count
    assert Repo.aggregate(Espreso.Orders.OrderItem, :count, :id) == before_items
  end

  test "complete_order marks ready orders picked up; unpaid cannot become ready" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, unpaid} =
      Orders.create_order(lines, %{
        customer_name: "Complete Unpaid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} = Orders.update_status(unpaid, "preparing")
    assert {:error, :payment_required} = Orders.update_status(preparing, "ready")

    {:ok, paid} =
      Orders.create_order(lines, %{
        customer_name: "Complete Paid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid)
    {:ok, paid_ready} = Orders.update_status(paid, "ready")
    assert {:ok, completed_paid} = Orders.complete_order(paid_ready)
    assert completed_paid.status == "completed"
    assert completed_paid.payment_status == "paid"
  end

  test "complete_order rejects cancelled and non-ready statuses; idempotent when completed" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, received} =
      Orders.create_order(lines, %{
        customer_name: "Complete Received",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:error, :invalid_status} = Orders.complete_order(received)

    {:ok, preparing} = Orders.update_status(received, "preparing")
    assert {:error, :invalid_status} = Orders.complete_order(preparing)

    {:ok, to_cancel} =
      Orders.create_order(lines, %{
        customer_name: "Complete Cancelled",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, cancelled} = Orders.cancel_order(to_cancel)
    assert {:error, :cancelled} = Orders.complete_order(cancelled)

    {:ok, ready} =
      Orders.create_order(lines, %{
        customer_name: "Complete Idempotent",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(ready)
    {:ok, ready} = Orders.update_status(ready, "ready")
    assert {:ok, completed} = Orders.complete_order(ready)
    assert {:ok, again} = Orders.complete_order(completed)
    assert again.id == completed.id
    assert again.status == "completed"
  end

  test "cancel_order voids unpaid received and preparing orders" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, received} =
      Orders.create_order(lines, %{
        customer_name: "Void Rec",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} =
      Orders.create_order(lines, %{
        customer_name: "Void Prep",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} = Orders.update_status(preparing, "preparing")

    assert {:ok, cancelled_received} = Orders.cancel_order(received)
    assert cancelled_received.status == "cancelled"
    assert Orders.status_label(cancelled_received.status) == "Cancelled"

    assert {:ok, cancelled_preparing} = Orders.cancel_order(preparing)
    assert cancelled_preparing.status == "cancelled"

    active_numbers = Enum.map(Orders.list_active_orders(), & &1.number)
    refute received.number in active_numbers
    refute preparing.number in active_numbers

    overview = Orders.dashboard_overview()
    assert overview.active_count == 0
    assert overview.todays_count == 0
    assert Orders.list_todays_orders() == []
  end

  test "cancel_order rejects paid, ready, and already cancelled orders" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, paid} =
      Orders.create_order(lines, %{
        customer_name: "Paid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid} = Orders.mark_paid(paid)
    assert {:error, :paid} = Orders.cancel_order(paid)

    {:ok, ready} =
      Orders.create_order(lines, %{
        customer_name: "Ready",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(ready)
    {:ok, ready} = Orders.update_status(ready, "ready")
    assert {:error, :paid} = Orders.cancel_order(ready)
    assert Enum.any?(Orders.list_recent_ready(), &(&1.id == ready.id))

    {:ok, to_cancel} =
      Orders.create_order(lines, %{
        customer_name: "Twice",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:ok, cancelled} = Orders.cancel_order(to_cancel)
    assert {:error, :invalid_status} = Orders.cancel_order(cancelled)
    refute Enum.any?(Orders.list_recent_ready(), &(&1.id == cancelled.id))
  end

  test "cancelling unpaid order does not change paid sales metrics" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, paid} =
      Orders.create_order(lines, %{
        customer_name: "Paid Keep",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid)

    {:ok, unpaid} =
      Orders.create_order(lines, %{
        customer_name: "Unpaid Void",
        fulfillment: :pickup,
        payment_method: :counter
      })

    before = Orders.sales_overview()
    assert {:ok, _} = Orders.cancel_order(unpaid)
    after_cancel = Orders.sales_overview()

    assert Decimal.equal?(before.todays_paid_total, after_cancel.todays_paid_total)
    assert before.todays_paid_count == after_cancel.todays_paid_count
  end

  test "dashboard_overview returns zeros when empty" do
    assert Orders.dashboard_overview() == %{
             active_count: 0,
             received_count: 0,
             preparing_count: 0,
             unpaid_active_count: 0,
             todays_count: 0
           }
  end

  test "dashboard_overview counts received, preparing, unpaid, and today" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, received} =
      Orders.create_order(lines, %{
        customer_name: "Ria",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} =
      Orders.create_order(lines, %{
        customer_name: "Pat",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} = Orders.update_status(preparing, "preparing")

    {:ok, paid_active} =
      Orders.create_order(lines, %{
        customer_name: "Kim",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _paid_active} = Orders.mark_paid(paid_active)

    {:ok, ready} =
      Orders.create_order(lines, %{
        customer_name: "Lex",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(ready)
    {:ok, ready} = Orders.update_status(ready, "ready")

    yesterday = DateTime.add(DateTime.utc_now(), -86_400, :second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^ready.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    overview = Orders.dashboard_overview()

    assert overview.active_count == 3
    assert overview.received_count == 1
    assert overview.preparing_count == 2
    assert overview.unpaid_active_count == 2
    assert overview.todays_count == 3
    assert received.status == "received"
    assert preparing.status == "preparing"
  end

  test "list_todays_orders returns empty when none today" do
    assert Orders.list_todays_orders() == []
  end

  test "list_todays_orders filters today only, newest first, and respects limit" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, older_today} =
      Orders.create_order(lines, %{
        customer_name: "Older",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, newer_today} =
      Orders.create_order(lines, %{
        customer_name: "Newer",
        fulfillment: :dine_in,
        table_number: "3",
        payment_method: :counter
      })

    {:ok, yesterday_order} =
      Orders.create_order(lines, %{
        customer_name: "Yesterday",
        fulfillment: :pickup,
        payment_method: :counter
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    earlier_today = DateTime.add(now, -60, :second)
    yesterday = DateTime.add(now, -86_400, :second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^older_today.id),
        set: [inserted_at: earlier_today, updated_at: earlier_today]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^newer_today.id),
        set: [inserted_at: now, updated_at: now]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_order.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    todays = Orders.list_todays_orders()
    assert Enum.map(todays, & &1.id) == [newer_today.id, older_today.id]
    refute Enum.any?(todays, &(&1.id == yesterday_order.id))
    refute Enum.any?(todays, &Ecto.assoc_loaded?(&1.items))

    limited = Orders.list_todays_orders(1)
    assert length(limited) == 1
    assert hd(limited).id == newer_today.id
  end

  test "sales_overview returns zeros when empty" do
    sales = Orders.sales_overview()
    assert sales.todays_paid_count == 0
    assert Decimal.equal?(sales.todays_paid_total, Decimal.new("0"))
  end

  test "sales_overview includes only today's paid order totals" do
    lines_75 = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
    lines_120 = [%{name: "Americano", size: "12oz", quantity: 1, price: Decimal.new("120")}]
    lines_200 = [%{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("200")}]

    {:ok, unpaid_today} =
      Orders.create_order(lines_75, %{
        customer_name: "Unpaid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_a} =
      Orders.create_order(lines_120, %{
        customer_name: "Paid A",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_b} =
      Orders.create_order(lines_200, %{
        customer_name: "Paid B",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, yesterday_paid} =
      Orders.create_order(lines_75, %{
        customer_name: "Yesterday Paid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid_a)
    {:ok, _} = Orders.mark_paid(paid_b)
    {:ok, yesterday_paid} = Orders.mark_paid(yesterday_paid)

    yesterday = DateTime.add(DateTime.utc_now(), -86_400, :second) |> DateTime.truncate(:second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_paid.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    sales = Orders.sales_overview()

    assert sales.todays_paid_count == 2
    assert Decimal.equal?(sales.todays_paid_total, Decimal.new("320"))
    assert unpaid_today.payment_status == "unpaid"
  end

  test "popular_products returns empty when none qualify" do
    assert Orders.popular_products() == []
  end

  test "popular_products ranks paid today by quantity and respects filters/limit" do
    {:ok, unpaid} =
      Orders.create_order(
        [
          %{name: "Espresso", size: nil, quantity: 5, price: Decimal.new("75")}
        ],
        %{customer_name: "Unpaid", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, paid_low} =
      Orders.create_order(
        [
          %{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("150")},
          %{name: "Americano", size: "8oz", quantity: 2, price: Decimal.new("110")}
        ],
        %{customer_name: "Paid Low", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, paid_high} =
      Orders.create_order(
        [
          %{name: "Americano", size: "12oz", quantity: 3, price: Decimal.new("120")},
          %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}
        ],
        %{customer_name: "Paid High", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, yesterday_paid} =
      Orders.create_order(
        [%{name: "Mocha", size: "12oz", quantity: 10, price: Decimal.new("160")}],
        %{customer_name: "Yesterday", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(paid_low)
    {:ok, _} = Orders.mark_paid(paid_high)
    {:ok, yesterday_paid} = Orders.mark_paid(yesterday_paid)

    yesterday = DateTime.add(DateTime.utc_now(), -86_400, :second) |> DateTime.truncate(:second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_paid.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    popular = Orders.popular_products()

    assert popular == [
             %{name: "Americano", quantity: 5},
             %{name: "Espresso", quantity: 1},
             %{name: "Latte", quantity: 1}
           ]

    assert unpaid.payment_status == "unpaid"
    refute Enum.any?(popular, &(&1.name == "Mocha"))

    assert Orders.popular_products(1) == [%{name: "Americano", quantity: 5}]
  end

  test "reports_overview returns zeros when empty" do
    reports = Orders.reports_overview()
    assert reports.period_paid_count == 0
    assert reports.period_days == 7
    assert Decimal.equal?(reports.period_paid_total, Decimal.new("0"))
  end

  test "reports_overview includes paid orders across last 7 Manila shop days only" do
    lines_75 = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
    lines_120 = [%{name: "Americano", size: "12oz", quantity: 1, price: Decimal.new("120")}]
    lines_200 = [%{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("200")}]

    {:ok, unpaid_today} =
      Orders.create_order(lines_75, %{
        customer_name: "Unpaid Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_today} =
      Orders.create_order(lines_120, %{
        customer_name: "Paid Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_mid} =
      Orders.create_order(lines_200, %{
        customer_name: "Paid Mid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_edge} =
      Orders.create_order(lines_75, %{
        customer_name: "Paid Edge",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_old} =
      Orders.create_order(lines_200, %{
        customer_name: "Paid Old",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid_today)
    {:ok, paid_mid} = Orders.mark_paid(paid_mid)
    {:ok, paid_edge} = Orders.mark_paid(paid_edge)
    {:ok, paid_old} = Orders.mark_paid(paid_old)

    today_start = Orders.shop_day_start_utc()
    mid_window = DateTime.add(today_start, -3, :day)
    edge_window = DateTime.add(today_start, -6, :day)
    too_old = DateTime.add(today_start, -7, :day)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^paid_mid.id),
        set: [inserted_at: mid_window, updated_at: mid_window]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^paid_edge.id),
        set: [inserted_at: edge_window, updated_at: edge_window]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^paid_old.id),
        set: [inserted_at: too_old, updated_at: too_old]
      )

    reports = Orders.reports_overview()

    assert reports.period_days == 7
    assert reports.period_paid_count == 3
    assert Decimal.equal?(reports.period_paid_total, Decimal.new("395"))
    assert unpaid_today.payment_status == "unpaid"
  end

  test "Manila shop day counts orders after UTC midnight but before Manila midnight as previous day" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
    today_start = Orders.shop_day_start_utc()

    # Just after Manila midnight (still previous UTC calendar date when offset is +8).
    after_manila_midnight = DateTime.add(today_start, 30 * 60, :second)
    before_manila_midnight = DateTime.add(today_start, -60, :second)

    {:ok, today_order} =
      Orders.create_order(lines, %{
        customer_name: "Manila Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, previous_order} =
      Orders.create_order(lines, %{
        customer_name: "Manila Yesterday",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, today_paid} =
      Orders.create_order(lines, %{
        customer_name: "Manila Paid Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, previous_paid} =
      Orders.create_order(
        [%{name: "Mocha", size: nil, quantity: 2, price: Decimal.new("80")}],
        %{
          customer_name: "Manila Paid Yesterday",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.mark_paid(today_paid)
    {:ok, _} = Orders.mark_paid(previous_paid)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^today_order.id),
        set: [inserted_at: after_manila_midnight, updated_at: after_manila_midnight]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^previous_order.id),
        set: [inserted_at: before_manila_midnight, updated_at: before_manila_midnight]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^today_paid.id),
        set: [inserted_at: after_manila_midnight, updated_at: after_manila_midnight]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^previous_paid.id),
        set: [inserted_at: before_manila_midnight, updated_at: before_manila_midnight]
      )

    todays = Orders.list_todays_orders()
    assert Enum.any?(todays, &(&1.id == today_order.id))
    refute Enum.any?(todays, &(&1.id == previous_order.id))

    overview = Orders.dashboard_overview()
    assert overview.todays_count == 2

    sales = Orders.sales_overview()
    assert sales.todays_paid_count == 1
    assert Decimal.equal?(sales.todays_paid_total, Decimal.new("75"))

    popular = Orders.popular_products()
    assert %{name: "Espresso", quantity: 1} in popular
    refute Enum.any?(popular, &(&1.name == "Mocha"))

    # Previous-day paid order still falls inside the 7-shop-day window.
    reports = Orders.reports_overview()
    assert reports.period_paid_count == 2
    assert Decimal.equal?(reports.period_paid_total, Decimal.new("235"))
  end

  test "list_todays_unpaid includes today's unpaid statuses and excludes paid, cancelled, and yesterday" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
    today_start = Orders.shop_day_start_utc()
    yesterday = DateTime.add(today_start, -60, :second)

    {:ok, received} =
      Orders.create_order(lines, %{
        customer_name: "Unpaid Received",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} =
      Orders.create_order(lines, %{
        customer_name: "Unpaid Preparing",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} = Orders.update_status(preparing, "preparing")

    {:ok, ready} =
      Orders.create_order(lines, %{
        customer_name: "Unpaid Ready",
        fulfillment: :pickup,
        payment_method: :counter
      })

    # Seed unpaid ready/completed via Repo — staff flow now blocks unpaid → ready.
    {1, _} =
      Espreso.Repo.update_all(from(o in Espreso.Orders.Order, where: o.id == ^ready.id),
        set: [status: "ready"]
      )

    ready = Orders.get_order_by_number!(ready.number)

    {:ok, completed} =
      Orders.create_order(lines, %{
        customer_name: "Unpaid Completed",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {1, _} =
      Espreso.Repo.update_all(from(o in Espreso.Orders.Order, where: o.id == ^completed.id),
        set: [status: "completed"]
      )

    completed = Orders.get_order_by_number!(completed.number)

    {:ok, paid} =
      Orders.create_order(lines, %{
        customer_name: "Paid Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid)

    {:ok, cancelled} =
      Orders.create_order(lines, %{
        customer_name: "Cancelled Unpaid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.cancel_order(cancelled)

    {:ok, yesterday_unpaid} =
      Orders.create_order(lines, %{
        customer_name: "Yesterday Unpaid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_unpaid.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    # Ensure deterministic newest-first ordering among today's unpaid.
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^completed.id),
        set: [inserted_at: now, updated_at: now]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^ready.id),
        set: [
          inserted_at: DateTime.add(now, -10, :second),
          updated_at: DateTime.add(now, -10, :second)
        ]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^preparing.id),
        set: [
          inserted_at: DateTime.add(now, -20, :second),
          updated_at: DateTime.add(now, -20, :second)
        ]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^received.id),
        set: [
          inserted_at: DateTime.add(now, -30, :second),
          updated_at: DateTime.add(now, -30, :second)
        ]
      )

    unpaid = Orders.list_todays_unpaid()
    unpaid_ids = Enum.map(unpaid, & &1.id)

    assert unpaid_ids == [completed.id, ready.id, preparing.id, received.id]
    refute paid.id in unpaid_ids
    refute cancelled.id in unpaid_ids
    refute yesterday_unpaid.id in unpaid_ids
    refute Enum.any?(unpaid, &Ecto.assoc_loaded?(&1.items))
  end

  describe "payment model layer 1" do
    alias Espreso.Accounts
    alias Espreso.BusinessSettings

    setup do
      {:ok, owner} =
        Accounts.register_user(%{
          name: "Payment Owner",
          email: "payment.owner@coffeespot.local",
          password: "password123",
          role: "owner"
        })

      {:ok, _} =
        BusinessSettings.update_as(owner, %{
          "business_name" => "CoffeeSpot",
          "address" => "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
          "phone" => "+639566728906",
          "email" => "payment@coffeespot.local",
          "hours_text" => "Daily · 8:00 AM – 10:00 PM",
          "instagram_url" => "https://www.instagram.com/coffeespot_lilac.marikina/",
          "facebook_url" => "https://www.facebook.com/profile.php?id=61572602608495",
          "tiktok_url" => "https://www.tiktok.com/@coffeespotlilac_"
        })

      :ok
    end

    test "online order in qrph_manual mode starts as awaiting_payment" do
      set_payments_mode!("qrph_manual")

      lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

      assert {:ok, order} =
               Orders.create_order(lines, %{
                 customer_name: "QR Guest",
                 fulfillment: :pickup,
                 payment_method: :online
               })

      assert order.payment_status == "awaiting_payment"
      assert Orders.payment_label(order) == "Awaiting QR payment"
    end

    test "staff can mark awaiting_payment paid with paid_via in qrph_manual mode" do
      set_payments_mode!("qrph_manual")

      lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "QR Confirm",
          fulfillment: :pickup,
          payment_method: :online
        })

      assert {:ok, paid} = Orders.mark_paid(order, paid_via: "gcash")
      assert paid.payment_status == "paid"
      assert paid.paid_via == "gcash"
      assert Orders.payment_label(paid) == "Paid via GCash"
    end

    test "payment_label reflects online wallet while awaiting QRPh payment" do
      set_payments_mode!("qrph_manual")

      lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

      assert {:ok, gcash_order} =
               Orders.create_order(lines, %{
                 customer_name: "GCash Guest",
                 fulfillment: :pickup,
                 payment_method: :online,
                 online_wallet: :gcash
               })

      assert Orders.payment_label(gcash_order) == "Awaiting GCash payment"

      assert {:ok, maya_order} =
               Orders.create_order(lines, %{
                 customer_name: "Maya Guest",
                 fulfillment: :pickup,
                 payment_method: :online,
                 online_wallet: :maya
               })

      assert Orders.payment_label(maya_order) == "Awaiting Maya payment"
    end

    test "online unpaid paymongo orders still block manual mark_paid" do
      set_payments_mode!("paymongo")

      lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "PayMongo Guest",
          fulfillment: :pickup,
          payment_method: :online
        })

      assert order.payment_status == "unpaid"
      assert {:error, :online_payment_required} = Orders.mark_paid(order, paid_via: "gcash")
    end

    test "counter mark_paid stores paid_via" do
      lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "Cash Guest",
          fulfillment: :pickup,
          payment_method: :counter
        })

      assert {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
      assert paid.payment_status == "paid"
      assert paid.paid_via == "cash"
    end

    test "paymongo webhook sets paid_via to paymongo" do
      set_payments_mode!("paymongo")

      lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "Webhook Guest",
          fulfillment: :pickup,
          payment_method: :online
        })

      assert {:ok, paid} = Orders.mark_paid_from_paymongo(order.number)
      assert paid.paid_via == "paymongo"
    end

    test "list_todays_unpaid includes awaiting_payment orders" do
      set_payments_mode!("qrph_manual")

      lines = [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}]

      {:ok, order} =
        Orders.create_order(lines, %{
          customer_name: "Unpaid QR",
          fulfillment: :pickup,
          payment_method: :online
        })

      unpaid_numbers = Orders.list_todays_unpaid() |> Enum.map(& &1.number)
      assert order.number in unpaid_numbers
    end
  end

  defp set_payments_mode!(mode) do
    setting = Espreso.BusinessSettings.get()

    setting
    |> Ecto.Changeset.change(%{payments_mode: mode})
    |> Repo.update!()
  end
end
