defmodule EspresoWeb.StaffMyShiftsLiveTest do
  use EspresoWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  setup %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Shift Barista",
        email: "my.shifts.barista@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Shift Manager",
        email: "my.shifts.manager@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, owner} =
      Accounts.register_user(%{
        name: "Shift Owner",
        email: "my.shifts.owner@test.local",
        password: "password123",
        role: "owner"
      })

    %{conn: conn, barista: barista, manager: manager, owner: owner}
  end

  test "unauthenticated visitors are redirected to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/staff/shifts")
  end

  test "barista, manager, and owner can open my shifts", %{
    conn: conn,
    barista: barista,
    manager: manager,
    owner: owner
  } do
    for user <- [barista, manager, owner] do
      {:ok, view, _html} = live(log_in(conn, user), ~p"/staff/shifts")

      assert has_element?(view, "#staff-my-shifts")
      assert has_element?(view, ".staff-shell-title", "My shifts")
      assert has_element?(view, "#staff-nav-my_shifts", "My shifts")
    end
  end

  test "home discovery tile and more nav link to my shifts", %{conn: conn, barista: barista} do
    {:ok, home, _html} = live(log_in(conn, barista), ~p"/staff")
    assert has_element?(home, "#staff-home-my-shifts", "My shifts")
    assert has_element?(home, "#staff-nav-my_shifts", "My shifts")
  end

  test "shows empty state when employee has no shifts", %{conn: conn, barista: barista} do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/shifts")

    assert has_element?(view, "#my-shifts-empty", "No shift history yet.")
    refute has_element?(view, "#my-shifts-current")
    refute has_element?(view, "#my-shifts-history")
  end

  test "renders current open shift with sales from PASS 5C helper", %{
    conn: conn,
    barista: barista
  } do
    assert {:ok, open} = StaffShifts.open_shift_for_login(barista)

    order =
      create_paid_pos!(barista,
        settled_at: DateTime.add(open.started_at, 60, :second),
        price: "150"
      )

    expected = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, open.id))
    assert expected.order_count == 1
    assert Decimal.equal?(expected.total, order.total)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/shifts")

    assert has_element?(view, "#my-shifts-current", "OPEN")
    assert has_element?(view, "#my-shifts-current", "1 order")
    assert has_element?(view, "#my-shifts-current", Menu.format_price(expected.total))
    refute has_element?(view, "#my-shifts-empty")
    refute has_element?(view, "#my-shift-#{open.id}")
  end

  test "renders completed shifts newest first including zero-sales", %{
    conn: conn,
    barista: barista
  } do
    morning =
      insert_shift!(barista, ~U[2026-09-09 01:00:00Z], ~U[2026-09-09 05:00:00Z])

    afternoon =
      insert_shift!(barista, ~U[2026-09-10 01:00:00Z], ~U[2026-09-10 05:00:00Z])

    create_paid_pos!(barista,
      settled_at: ~U[2026-09-10 02:00:00Z],
      price: "200"
    )

    afternoon_sales = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, afternoon.id))
    morning_sales = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, morning.id))

    assert afternoon_sales.order_count == 1
    assert morning_sales.order_count == 0

    {:ok, view, html} = live(log_in(conn, barista), ~p"/staff/shifts")

    refute has_element?(view, "#my-shifts-current")
    assert has_element?(view, "#my-shift-#{afternoon.id}", "1 order")

    assert has_element?(
             view,
             "#my-shift-#{afternoon.id}",
             Menu.format_price(afternoon_sales.total)
           )

    assert has_element?(view, "#my-shift-#{morning.id}", "0 orders")
    assert has_element?(view, "#my-shift-#{morning.id}", "₱0")

    afternoon_pos = :binary.match(html, "my-shift-#{afternoon.id}") |> elem(0)
    morning_pos = :binary.match(html, "my-shift-#{morning.id}") |> elem(0)
    assert afternoon_pos < morning_pos
  end

  test "never shows another employee's shifts or sales", %{
    conn: conn,
    barista: barista,
    manager: manager
  } do
    other_shift =
      insert_shift!(manager, ~U[2026-09-10 01:00:00Z], ~U[2026-09-10 05:00:00Z])

    create_paid_pos!(manager,
      settled_at: ~U[2026-09-10 02:00:00Z],
      price: "500"
    )

    own_shift =
      insert_shift!(barista, ~U[2026-09-10 06:00:00Z], ~U[2026-09-10 08:00:00Z])

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/shifts")

    assert has_element?(view, "#my-shift-#{own_shift.id}")
    refute has_element?(view, "#my-shift-#{other_shift.id}")
    refute has_element?(view, "#my-shifts-current")
    refute render(view) =~ "₱500"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp insert_shift!(user, started_at, ended_at, end_reason \\ "logout") do
    {:ok, shift} =
      %StaffShift{}
      |> StaffShift.open_changeset(%{user_id: user.id, started_at: started_at})
      |> Repo.insert()

    shift
    |> StaffShift.close_changeset(%{ended_at: ended_at, end_reason: end_reason})
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

    Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [settled_at: settled_at])
    Repo.get!(Order, order.id)
  end

  defp insert_pos_line!(amount) do
    category =
      %Espreso.Menu.Category{}
      |> Espreso.Menu.Category.changeset(%{
        name: "MyShifts-#{System.unique_integer([:positive])}"
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
