defmodule EspresoWeb.StaffCashOutLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.CashOuts
  alias Espreso.Menu
  alias Espreso.Orders
  alias Espreso.Shifts
  alias Espreso.StaffShifts

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  setup do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Mia",
        email: "mia-cash-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Ana",
        email: "ana-cash-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owen",
        email: "owen-cash-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
      })

    %{barista: barista, manager: manager, owner: owner}
  end

  test "barista with open shift can record Cash Out", %{conn: conn, barista: barista} do
    assert {:ok, _} = StaffShifts.open_shift_for_login(barista)
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/cash-out")

    refute has_element?(view, "#staff-cash-out-blocked")
    assert has_element?(view, "#staff-cash-out-form")

    view
    |> form("#staff-cash-out-form", %{
      cash_out: %{amount: "500", category: "Supplies", note: "Cleaning supplies"}
    })
    |> render_submit()

    assert has_element?(view, "#staff-cash-out-confirm", "Cash Out recorded")
    assert has_element?(view, "#staff-cash-out-confirm", "₱500")
    assert has_element?(view, "#staff-cash-out-total", "₱500")
    assert has_element?(view, "#staff-cash-out-list", "Supplies")
    assert has_element?(view, "#staff-cash-out-list", "Cleaning supplies")
    assert has_element?(view, "#staff-cash-out-list", "Mia")
  end

  test "barista without open shift is blocked", %{conn: conn, barista: barista} do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/cash-out")

    assert has_element?(view, "#staff-cash-out-blocked")
    assert has_element?(view, "#staff-cash-out-blocked-copy", "open staff shift")
    refute has_element?(view, "#staff-cash-out-form")
  end

  test "manager and owner can access Cash Out", %{conn: conn, manager: manager, owner: owner} do
    {:ok, manager_view, _} = live(log_in(conn, manager), ~p"/staff/cash-out")
    assert has_element?(manager_view, "#staff-cash-out-form")

    manager_view
    |> form("#staff-cash-out-form", %{cash_out: %{amount: "80", category: "Ingredients"}})
    |> render_submit()

    assert has_element?(manager_view, "#staff-cash-out-total", "₱80")

    {:ok, owner_view, _} = live(log_in(conn, owner), ~p"/staff/cash-out")
    assert has_element?(owner_view, "#staff-cash-out-form")
  end

  test "manager can void a Cash Out", %{conn: conn, manager: manager} do
    assert {:ok, cash_out} =
             CashOuts.create_cash_out(manager, %{amount: "90", category: "Cleaning"})

    {:ok, view, _} = live(log_in(conn, manager), ~p"/staff/cash-out")

    view
    |> form("#staff-cash-out-void-form-#{cash_out.id}", %{reason: "Wrong amount"})
    |> render_submit()

    assert has_element?(view, "#staff-cash-out-voided-#{cash_out.id}", "VOIDED")
    assert has_element?(view, "#staff-cash-out-total", "₱0")
  end

  test "home and more nav include Cash Out", %{conn: conn, barista: barista, manager: manager} do
    assert {:ok, _} = StaffShifts.open_shift_for_login(barista)

    {:ok, barista_home, _} = live(log_in(conn, barista), ~p"/staff")
    assert has_element?(barista_home, "#staff-home-cash-out", "Cash Out")
    assert has_element?(barista_home, "#staff-nav-cash_out", "Cash Out")

    {:ok, manager_home, _} = live(log_in(conn, manager), ~p"/staff")
    assert has_element?(manager_home, "#staff-home-cash-out", "Cash Out")
    assert has_element?(manager_home, "#staff-nav-cash_out", "Cash Out")
  end

  test "Close Shift shows Cash Out total and details", %{conn: conn, manager: manager} do
    assert {:ok, _} =
             CashOuts.create_cash_out(manager, %{
               amount: "500",
               category: "Ingredients",
               note: "Ice and supplies"
             })

    assert {:ok, _} =
             CashOuts.create_cash_out(manager, %{
               amount: "300",
               category: "Cleaning",
               note: "Cleaning materials"
             })

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Cash", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    {:ok, view, _} = live(log_in(conn, manager), ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-cash", "₱75")

    assert has_element?(
             view,
             "#staff-shift-close-cash-out-total",
             Menu.format_price(Decimal.new("800"))
           )

    assert has_element?(view, "#staff-shift-close-cash-out-list", "Ingredients")
    assert has_element?(view, "#staff-shift-close-cash-out-list", "Ice and supplies")
    assert has_element?(view, "#staff-shift-close-cash-out-list", "Cleaning")

    assert is_nil(Shifts.get_todays_close())
  end

  test "cash out history empty state keeps today form available", %{conn: conn, manager: manager} do
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/staff/cash-out")

    assert has_element?(view, "#staff-cash-out-history-empty", "No previous cash outs yet.")
    assert has_element?(view, "#staff-cash-out-form")
    refute has_element?(view, "#staff-cash-out-history-more")
  end

  test "cash out history groups previous days and paginates", %{conn: conn, manager: manager} do
    today = Orders.shop_date_today()

    for {offset, amount, note, void?} <- [
          {3, "90", "Day three", false},
          {2, "50", "Day two voided", true},
          {2, "120", "Day two kept", false},
          {1, "150", "Day one", false}
        ] do
      cash_out =
        insert_history_cash_out!(manager, Date.add(today, -offset), %{
          amount: Decimal.new(amount),
          note: note
        })

      if void? do
        assert {:ok, _} = CashOuts.void_cash_out(cash_out, manager, "Correction")
      end
    end

    with_cash_out_history_page_size(2, fn ->
      {:ok, view, _html} = live(log_in(conn, manager), ~p"/staff/cash-out")

      assert has_element?(view, "#staff-cash-out-history")

      assert has_element?(
               view,
               "#staff-cash-out-history-day-#{Date.to_iso8601(Date.add(today, -1))}"
             )

      assert has_element?(
               view,
               "#staff-cash-out-history-day-#{Date.to_iso8601(Date.add(today, -2))}"
             )

      refute has_element?(
               view,
               "#staff-cash-out-history-day-#{Date.to_iso8601(Date.add(today, -3))}"
             )

      assert has_element?(view, "#staff-cash-out-history-days", "Day one")
      assert has_element?(view, "#staff-cash-out-history-days", "₱150")
      assert has_element?(view, "#staff-cash-out-history-days", "Day two kept")
      assert has_element?(view, "#staff-cash-out-history-days", "₱120")
      assert has_element?(view, "#staff-cash-out-history-days", "VOIDED")
      assert has_element?(view, "#staff-cash-out-history-days", "Correction")
      assert has_element?(view, "#staff-cash-out-history-more", "Load more")
      assert has_element?(view, "#staff-cash-out-form")

      view |> element("#staff-cash-out-history-more") |> render_click()

      assert has_element?(
               view,
               "#staff-cash-out-history-day-#{Date.to_iso8601(Date.add(today, -3))}"
             )

      assert has_element?(view, "#staff-cash-out-history-days", "Day three")
      refute has_element?(view, "#staff-cash-out-history-more")

      html = render(view)

      assert length(Regex.scan(~r/id="staff-cash-out-history-day-\d{4}-\d{2}-\d{2}"/, html)) == 3

      view
      |> form("#staff-cash-out-form", %{cash_out: %{amount: "33", category: "Other"}})
      |> render_submit()

      assert has_element?(view, "#staff-cash-out-total", "₱33")

      assert has_element?(
               view,
               "#staff-cash-out-history-day-#{Date.to_iso8601(Date.add(today, -3))}"
             )
    end)
  end

  test "inactive staff cannot open cash out history route", %{conn: conn} do
    {:ok, inactive} =
      Accounts.register_user(%{
        name: "Inactive Cash",
        email: "inactive-cash-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    assert {:ok, _} = Accounts.update_user(inactive, %{active: false})

    assert {:error, {:redirect, %{to: to}}} =
             live(log_in(conn, inactive), ~p"/staff/cash-out")

    assert to in [~p"/login", ~p"/staff", ~p"/dashboard"]
  end

  defp insert_history_cash_out!(user, shop_date, attrs) do
    {:ok, cash_out} =
      %Espreso.CashOuts.CashOut{}
      |> Espreso.CashOuts.CashOut.create_changeset(%{
        amount: Map.fetch!(attrs, :amount),
        category: Map.get(attrs, :category, "Other"),
        note: Map.get(attrs, :note),
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second),
        shop_date: shop_date,
        status: "recorded",
        created_by_user_id: user.id
      })
      |> Espreso.Repo.insert()

    Espreso.Repo.preload(cash_out, :created_by_user)
  end

  defp with_cash_out_history_page_size(size, fun)
       when is_integer(size) and is_function(fun, 0) do
    previous = Application.get_env(:espreso, :cash_out_history_page_size)
    Application.put_env(:espreso, :cash_out_history_page_size, size)

    try do
      fun.()
    after
      if is_nil(previous) do
        Application.delete_env(:espreso, :cash_out_history_page_size)
      else
        Application.put_env(:espreso, :cash_out_history_page_size, previous)
      end
    end
  end
end
