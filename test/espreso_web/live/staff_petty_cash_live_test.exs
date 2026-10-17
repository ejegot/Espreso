defmodule EspresoWeb.StaffPettyCashLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.PettyCash
  alias Espreso.StaffShifts

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  setup do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Petty Barista",
        email: "petty-live-barista-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Petty Manager",
        email: "petty-live-manager-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    %{barista: barista, manager: manager}
  end

  test "staff can record and review digital petty-cash purchases", %{
    conn: conn,
    barista: barista
  } do
    assert {:ok, _shift} = StaffShifts.open_shift_for_login(barista)
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff/petty-cash")

    assert has_element?(view, "#staff-petty-cash-balance", "₱500")
    assert has_element?(view, "#staff-petty-cash-form")
    assert has_element?(view, "#staff-petty-cash-form", "What was purchased?")

    view
    |> form("#staff-petty-cash-form", %{
      petty_cash: %{amount: "50", category: "Ingredients", note: "Bag of ice"}
    })
    |> render_submit()

    assert has_element?(view, "#staff-petty-cash-list", "Bag of ice")
    assert has_element?(view, "#staff-petty-cash-list", "₱50")
    assert has_element?(view, "#staff-petty-cash-balance", "₱450")
    assert has_element?(view, "#staff-petty-cash-total", "₱50")

    assert Decimal.equal?(
             PettyCash.total_for_shop_date(Espreso.Orders.shop_date_today()),
             Decimal.new("50")
           )
  end

  test "manager can void a mistaken petty-cash entry", %{conn: conn, manager: manager} do
    assert {:ok, entry} =
             PettyCash.create_entry(manager, %{
               amount: "40",
               category: "Other",
               note: "Wrong item"
             })

    {:ok, view, _html} = live(log_in(conn, manager), ~p"/staff/petty-cash")
    view |> element("#staff-petty-cash-entry-#{entry.id} button") |> render_click()

    view
    |> form("#staff-petty-cash-void-modal form", %{
      entry_id: entry.id,
      reason: "Duplicate purchase"
    })
    |> render_submit()

    assert has_element?(view, "#staff-petty-cash-entry-#{entry.id}", "VOIDED")
    assert has_element?(view, "#staff-petty-cash-total", "₱0")
  end
end
