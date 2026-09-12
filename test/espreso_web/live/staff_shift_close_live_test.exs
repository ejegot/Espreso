defmodule EspresoWeb.StaffShiftCloseLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Repo
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  setup %{conn: conn} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Ana",
        email: "ana-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, manager.id)

    %{conn: conn, manager: manager}
  end

  test "manager sees close hierarchy and can record shift close", %{conn: conn, manager: manager} do
    {:ok, cash_order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Cash Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, gcash_order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("140")}],
        %{customer_name: "Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(cash_order, paid_via: "cash")
    {:ok, _} = Orders.mark_paid(gcash_order, paid_via: "gcash")

    {:ok, view, _html} = live(conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-status", "Open")
    assert has_element?(view, "#staff-shift-close-cash", "Cash settled")
    assert has_element?(view, "#staff-shift-close-cash", "₱75")
    assert has_element?(view, "#staff-shift-close-counted-field", "Counted drawer cash")
    assert has_element?(view, "#staff-shift-close-counted-hint", "Optional")
    assert has_element?(view, "#staff-shift-close-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-system", "System paid")
    assert has_element?(view, "#staff-shift-close-system", "₱215")
    assert has_element?(view, "#staff-shift-close-prepare", "Record close")
    refute has_element?(view, "#staff-shift-close-confirm")
    refute has_element?(view, "#staff-shift-close-timed-out")

    view
    |> form("#staff-shift-close-form", %{close: %{counted_cash: "80", notes: "Balanced"}})
    |> render_submit()

    assert has_element?(view, "#staff-shift-close-confirm", "Record today’s close?")
    assert has_element?(view, "#staff-shift-close-confirm-cash", "Counted drawer cash · ₱80")
    assert has_element?(view, "#staff-shift-close-submit", "Confirm seal")

    view
    |> element("#staff-shift-close-submit")
    |> render_click()

    assert has_element?(view, "#staff-shift-close-status", "Shift closed")
    assert has_element?(view, "#staff-shift-close-done", "Shift closed")
    assert has_element?(view, "#staff-shift-close-done-meta", "Ana")
    assert has_element?(view, "#staff-shift-close-sealed-system", "₱215")
    assert has_element?(view, "#staff-shift-close-sealed-system", "2 orders")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "Cash")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "₱75")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-sealed-cash", "₱75")
    assert has_element?(view, "#staff-shift-close-sealed-counted", "₱80")
    assert has_element?(view, "#staff-shift-close-sealed-notes", "Balanced")
    assert has_element?(view, "#staff-shift-close-done a[href='/staff']", "Back to Home")
    assert has_element?(view, "#staff-shift-close-done a[href='/dashboard']", "Back to Dashboard")

    assert has_element?(
             view,
             "#staff-shift-close-done a[href='/transactions']",
             "View Transactions"
           )

    refute has_element?(view, "#staff-shift-close-logout")
    refute has_element?(view, "#staff-shift-close-prepare")
    refute has_element?(view, "#staff-shift-close-submit")

    close = Shifts.get_todays_close()
    assert close.closed_by_user_id == manager.id
    assert close.notes == "Balanced"
    assert Decimal.equal?(close.system_total, Decimal.new("215"))
    assert close.system_count == 2
    assert Decimal.equal?(close.counted_cash, Decimal.new("80"))
    assert StaffShifts.list_shifts_for_user(manager.id) == []
  end

  test "closed state shows sealed snapshot not later live totals", %{conn: conn, manager: manager} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("140")}],
        %{customer_name: "Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "gcash")

    assert {:ok, _close} =
             Shifts.record_close(manager, %{
               "counted_cash" => "140",
               "notes" => "End of day"
             })

    {:ok, late} =
      Orders.create_order(
        [%{name: "Americano", size: nil, quantity: 1, price: Decimal.new("95")}],
        %{customer_name: "Late", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(late, paid_via: "cash")

    live_total = Orders.todays_paid_breakdown().total
    assert Decimal.equal?(live_total, Decimal.new("235"))

    {:ok, view, _html} = live(conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-status", "Shift closed")

    assert has_element?(
             view,
             "#staff-shift-close-sealed-system",
             Menu.format_price(Decimal.new("140"))
           )

    assert has_element?(view, "#staff-shift-close-sealed-system", "1 orders")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-sealed-cash", "₱0")
    assert has_element?(view, "#staff-shift-close-sealed-counted", "₱140")
    refute has_element?(view, "#staff-shift-close-sealed-system", "₱235")
    refute has_element?(view, "#staff-shift-close-form")
  end

  test "prepare close with blank counted cash states no drawer count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/staff/close")

    view
    |> form("#staff-shift-close-form", %{close: %{counted_cash: "", notes: ""}})
    |> render_submit()

    assert has_element?(view, "#staff-shift-close-confirm-cash", "No drawer cash count entered.")
  end

  test "last-active barista can access and complete close with Time Out", %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Mia",
        email: "mia-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    assert {:ok, open} = StaffShifts.open_shift_for_login(barista)

    barista_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    {:ok, view, _html} = live(barista_conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-status", "Open")
    refute has_element?(view, "#staff-shift-close-blocked")

    view
    |> form("#staff-shift-close-form", %{close: %{counted_cash: "40", notes: ""}})
    |> render_submit()

    assert has_element?(view, "#staff-shift-close-confirm", "Your staff shift will also end")

    view
    |> element("#staff-shift-close-submit")
    |> render_click()

    assert has_element?(view, "#staff-shift-close-status", "Shift closed")
    assert has_element?(view, "#staff-shift-close-timed-out")
    assert has_element?(view, "#staff-shift-close-logout", "Log out")
    refute has_element?(view, "#staff-shift-close-done a[href='/dashboard']")

    closed = Repo.get!(StaffShift, open.id)
    assert closed.end_reason == "shift_close"
    assert %Shifts.ShiftClose{} = Shifts.get_todays_close()
    assert is_nil(StaffShifts.get_open_shift(barista))
  end

  test "non-last-active barista sees blocked state", %{conn: conn} do
    {:ok, a} =
      Accounts.register_user(%{
        name: "Alex",
        email: "alex-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, b} =
      Accounts.register_user(%{
        name: "Bea",
        email: "bea-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    assert {:ok, _} = StaffShifts.open_shift_for_login(a)
    assert {:ok, _} = StaffShifts.open_shift_for_login(b)

    a_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, a.id)

    {:ok, view, _html} = live(a_conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-status", "Waiting on staff")
    assert has_element?(view, "#staff-shift-close-blocked")

    assert has_element?(
             view,
             "#staff-shift-close-blocked-copy",
             "Another staff member is still on shift"
           )

    assert has_element?(view, "#staff-shift-close-blocked-staff", "Bea")
    refute has_element?(view, "#staff-shift-close-form")
    assert is_nil(Shifts.get_todays_close())
  end

  test "owner can open close shift", %{conn: conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
      })

    owner_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, owner.id)

    {:ok, view, _html} = live(owner_conn, ~p"/staff/close")
    assert has_element?(view, "#staff-shift-close-prepare", "Record close")
  end

  test "close history empty state keeps close action available", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-history-empty", "No previous closes yet.")
    assert has_element?(view, "#staff-shift-close-prepare", "Record close")
    refute has_element?(view, "#staff-shift-close-history-more")
  end

  test "close history lists sealed snapshots newest first and paginates", %{
    conn: conn,
    manager: manager
  } do
    today = Orders.shop_date_today()

    for {offset, total, note} <- [
          {3, "90", "Day three"},
          {2, "120", "Day two"},
          {1, "150", "Day one"}
        ] do
      insert_close_snapshot!(manager, Date.add(today, -offset), %{
        system_total: Decimal.new(total),
        notes: note
      })
    end

    with_close_history_page_size(2, fn ->
      {:ok, view, _html} = live(conn, ~p"/staff/close")

      assert has_element?(view, "#staff-shift-close-history")

      assert has_element?(
               view,
               "#staff-shift-close-history-#{Date.to_iso8601(Date.add(today, -1))}"
             )

      assert has_element?(
               view,
               "#staff-shift-close-history-#{Date.to_iso8601(Date.add(today, -2))}"
             )

      refute has_element?(
               view,
               "#staff-shift-close-history-#{Date.to_iso8601(Date.add(today, -3))}"
             )

      assert has_element?(view, "#staff-shift-close-history-list", "Day one")
      assert has_element?(view, "#staff-shift-close-history-list", "₱150")
      assert has_element?(view, "#staff-shift-close-history-list", "Ana")
      assert has_element?(view, "#staff-shift-close-history-more", "Load more")
      assert has_element?(view, "#staff-shift-close-prepare", "Record close")

      view |> element("#staff-shift-close-history-more") |> render_click()

      assert has_element?(
               view,
               "#staff-shift-close-history-#{Date.to_iso8601(Date.add(today, -3))}"
             )

      assert has_element?(view, "#staff-shift-close-history-list", "Day three")
      refute has_element?(view, "#staff-shift-close-history-more")

      html = render(view)
      assert length(Regex.scan(~r/id="staff-shift-close-history-\d{4}-\d{2}-\d{2}"/, html)) == 3
    end)
  end

  test "inactive staff cannot open close history route", %{conn: conn} do
    {:ok, inactive} =
      Accounts.register_user(%{
        name: "Inactive",
        email: "inactive-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    assert {:ok, _} = Accounts.update_user(inactive, %{active: false})

    inactive_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, inactive.id)

    assert {:error, {:redirect, %{to: to}}} = live(inactive_conn, ~p"/staff/close")
    assert to in [~p"/login", ~p"/staff", ~p"/dashboard"]
  end

  defp insert_close_snapshot!(user, shop_date, attrs) do
    {:ok, close} =
      %Espreso.Shifts.ShiftClose{}
      |> Espreso.Shifts.ShiftClose.changeset(%{
        shop_date: shop_date,
        system_total: Map.fetch!(attrs, :system_total),
        system_count: Map.get(attrs, :system_count, 1),
        by_via:
          Map.get(attrs, :by_via, %{
            "cash" => %{
              "total" => Decimal.to_string(Map.fetch!(attrs, :system_total)),
              "count" => 1
            }
          }),
        counted_cash: Map.get(attrs, :counted_cash),
        notes: Map.get(attrs, :notes),
        closed_by_user_id: user.id,
        closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    close
  end

  defp with_close_history_page_size(size, fun) when is_integer(size) and is_function(fun, 0) do
    previous = Application.get_env(:espreso, :close_history_page_size)
    Application.put_env(:espreso, :close_history_page_size, size)

    try do
      fun.()
    after
      if is_nil(previous) do
        Application.delete_env(:espreso, :close_history_page_size)
      else
        Application.put_env(:espreso, :close_history_page_size, previous)
      end
    end
  end
end
