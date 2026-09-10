defmodule EspresoWeb.StaffAttendanceLiveTest do
  use EspresoWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias Espreso.StaffShifts.StaffShift

  setup %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Attendance Barista",
        email: "attendance.barista@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Attendance Manager",
        email: "attendance.manager@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, owner} =
      Accounts.register_user(%{
        name: "Attendance Owner",
        email: "attendance.owner@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, worker} =
      Accounts.register_user(%{
        name: "Ana Worker",
        email: "ana.worker.attendance@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, worker_b} =
      Accounts.register_user(%{
        name: "Ben Worker",
        email: "ben.worker.attendance@test.local",
        password: "password123",
        role: "barista"
      })

    %{
      conn: conn,
      barista: barista,
      manager: manager,
      owner: owner,
      worker: worker,
      worker_b: worker_b
    }
  end

  test "barista cannot access staff attendance", %{conn: conn, barista: barista} do
    assert {:error, {:redirect, %{to: "/orders"}}} =
             live(log_in(conn, barista), ~p"/staff/attendance")
  end

  test "manager and owner can access staff attendance", %{
    conn: conn,
    manager: manager,
    owner: owner
  } do
    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff/attendance")
    assert has_element?(manager_view, "#staff-attendance")
    assert has_element?(manager_view, ".staff-shell-title", "Staff attendance")
    assert has_element?(manager_view, "#staff-nav-attendance", "Staff attendance")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff/attendance")
    assert has_element?(owner_view, "#staff-attendance")
  end

  test "shows empty state when no staff shifts today", %{conn: conn, manager: manager} do
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/staff/attendance")

    assert has_element?(view, "#staff-attendance-empty", "No staff shifts today.")
    refute has_element?(view, "#staff-attendance-working")
    refute has_element?(view, "#staff-attendance-completed")
  end

  test "renders open and completed shifts with PASS 5C sales", %{
    conn: conn,
    manager: manager,
    worker: worker,
    worker_b: worker_b
  } do
    {day_start, _day_end} = Orders.shop_day_bounds_utc(Orders.shop_date_today())
    open_started = DateTime.add(day_start, 2 * 3600, :second) |> DateTime.truncate(:second)

    closed_started = DateTime.add(day_start, 3 * 3600, :second) |> DateTime.truncate(:second)
    closed_ended = DateTime.add(day_start, 8 * 3600, :second) |> DateTime.truncate(:second)

    open = insert_open_shift!(worker, open_started)
    closed = insert_shift!(worker_b, closed_started, closed_ended)

    paid =
      create_paid_pos!(worker,
        settled_at: DateTime.add(open_started, 30 * 60, :second),
        price: "150"
      )

    zero_sales = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, closed.id))
    open_sales = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, open.id))

    assert open_sales.order_count == 1
    assert Decimal.equal?(open_sales.total, paid.total)
    assert zero_sales.order_count == 0

    {:ok, view, _html} = live(log_in(conn, manager), ~p"/staff/attendance")

    assert has_element?(view, "#staff-attendance-working")
    assert has_element?(view, "#attendance-shift-#{open.id}", "Ana Worker")
    assert has_element?(view, "#attendance-shift-#{open.id}", "OPEN")
    assert has_element?(view, "#attendance-shift-#{open.id}", "1 order")
    assert has_element?(view, "#attendance-shift-#{open.id}", Menu.format_price(open_sales.total))

    assert has_element?(view, "#staff-attendance-completed")
    assert has_element?(view, "#attendance-shift-#{closed.id}", "Ben Worker")
    assert has_element?(view, "#attendance-shift-#{closed.id}", "0 orders")
    assert has_element?(view, "#attendance-shift-#{closed.id}", "₱0")
    refute has_element?(view, "#staff-attendance-empty")
  end

  test "attributes sales to settler not creator and excludes customer orders", %{
    conn: conn,
    manager: manager,
    worker: worker,
    worker_b: worker_b
  } do
    {day_start, _} = Orders.shop_day_bounds_utc(Orders.shop_date_today())
    started = DateTime.add(day_start, 2 * 3600, :second) |> DateTime.truncate(:second)

    shift_a = insert_open_shift!(worker, started)
    shift_b = insert_open_shift!(worker_b, started)

    {:ok, unpaid} =
      Orders.create_order([insert_pos_line!("120")], %{
        customer_name: "Walk-in",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :unpaid,
        source: :pos
      })

    assert {:ok, paid} =
             Orders.mark_paid(unpaid,
               paid_via: "cash",
               settled_by_user_id: worker_b.id,
               settlement_source: "staff_orders"
             )

    set_settled_at!(paid, DateTime.add(started, 600, :second))

    {:ok, customer} =
      Orders.create_order([insert_pos_line!("90")], %{
        customer_name: "QR Guest",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :unpaid,
        source: :customer
      })

    {:ok, customer_paid} =
      Orders.mark_paid(customer,
        paid_via: "cash",
        settled_by_user_id: worker.id,
        settlement_source: "staff_orders"
      )

    set_settled_at!(customer_paid, DateTime.add(started, 700, :second))

    sales_a = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, shift_a.id))
    sales_b = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, shift_b.id))

    assert sales_a.order_count == 0
    assert sales_b.order_count == 1

    {:ok, view, _html} = live(log_in(conn, manager), ~p"/staff/attendance")

    assert has_element?(view, "#attendance-shift-#{shift_a.id}", "0 orders")
    assert has_element?(view, "#attendance-shift-#{shift_b.id}", "1 order")
    assert has_element?(view, "#attendance-shift-#{shift_b.id}", Menu.format_price(sales_b.total))
  end

  test "my shifts remains personal for barista", %{conn: conn, barista: barista, worker: worker} do
    {day_start, _} = Orders.shop_day_bounds_utc(Orders.shop_date_today())
    started = DateTime.add(day_start, 2 * 3600, :second) |> DateTime.truncate(:second)
    other = insert_open_shift!(worker, started)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/shifts")
    assert has_element?(view, "#staff-my-shifts")
    refute has_element?(view, "#attendance-shift-#{other.id}")
    refute has_element?(view, "#my-shift-#{other.id}")
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp insert_open_shift!(user, started_at) do
    {:ok, shift} =
      %StaffShift{}
      |> StaffShift.open_changeset(%{user_id: user.id, started_at: started_at})
      |> Repo.insert()

    shift
  end

  defp insert_shift!(user, started_at, ended_at) do
    insert_open_shift!(user, started_at)
    |> StaffShift.close_changeset(%{ended_at: ended_at, end_reason: "logout"})
    |> Repo.update!()
  end

  defp create_paid_pos!(user, opts) do
    settled_at = Keyword.fetch!(opts, :settled_at)
    price = Keyword.get(opts, :price, "100")

    {:ok, order} =
      Orders.create_order([insert_pos_line!(price)], %{
        customer_name: "Walk-in",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: "cash",
        source: :pos,
        settled_by_user_id: user.id,
        settlement_source: "pos"
      })

    set_settled_at!(order, settled_at)
  end

  defp set_settled_at!(%Order{id: id}, %DateTime{} = settled_at) do
    Repo.update_all(from(o in Order, where: o.id == ^id), set: [settled_at: settled_at])
    Repo.get!(Order, id)
  end

  defp insert_pos_line!(amount) do
    category =
      %Espreso.Menu.Category{}
      |> Espreso.Menu.Category.changeset(%{
        name: "Att-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    product =
      %Espreso.Menu.Product{}
      |> Espreso.Menu.Product.changeset(%{
        name: "Drink-#{System.unique_integer([:positive])}",
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
end
