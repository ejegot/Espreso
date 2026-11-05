defmodule EspresoWeb.StaffCloseMyShiftLiveTest do
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
        name: "Close Shift Barista",
        email: "close.shift.barista-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, owner} =
      Accounts.register_user(%{
        name: "Close Shift Owner",
        email: "close.shift.owner-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    %{conn: conn, barista: barista, owner: owner}
  end

  describe "end my shift" do
    test "shows open shift details", %{conn: conn, barista: barista} do
      # Open a shift
      {:ok, _shift} = StaffShifts.open_shift_for_login(barista)

      {:ok, _lv, html} = live(conn, "/staff/close-my-shift")

      assert html =~ "Close your shift"
      assert html =~ "Shift details"
      assert html =~ "Started at:"
    end

    test "redirects if no open shift", %{conn: conn} do
      # Should redirect to home with flash message
      {:error, {:live_redirect, redirect}} = live(conn, "/staff/close-my-shift")
      assert redirect.to == "/staff"
      assert redirect.flash["info"] =~ "open shift"
    end

    test "closes shift and records ended_at with sales summary", %{conn: conn, barista: barista} do
      # Open a shift
      {:ok, shift} = StaffShifts.open_shift_for_login(barista)
      assert is_nil(shift.ended_at)

      {:ok, lv, _html} = live(conn, "/staff/close-my-shift")

      # Should show shift details including sales
      html = render(lv)
      assert html =~ "Shift details"
      assert html =~ "Orders completed"
      assert html =~ "Your sales today"

      # Confirm close
      lv
      |> element("button", "End My Shift")
      |> render_click()

      # Verify button changes to confirmation
      html = render(lv)
      assert html =~ "Yes, end my shift"

      # Click confirmation
      lv
      |> element("button", "Yes, end my shift")
      |> render_click()

      # Verify shift is closed in database
      closed_shift = StaffShifts.get_open_shift(barista.id)
      assert is_nil(closed_shift), "Shift should be closed"

      # Verify the UI shows shift closed with sales
      html = render(lv)
      assert html =~ "Shift closed"
      assert html =~ "Your sales"
    end

    test "shows only today's sales before and after closing an overnight shift", %{
           conn: conn,
           barista: barista
         } do
      today = Orders.shop_date_today()
      {today_start, today_end} = Orders.shop_day_bounds_utc(today)
      yesterday = Date.add(today, -1)
      {_, yesterday_end} = Orders.shop_day_bounds_utc(yesterday)

      started_at =
        DateTime.add(yesterday_end, -1800, :second)
        |> DateTime.truncate(:second)

      {:ok, shift} =
        %StaffShift{}
        |> StaffShift.open_changeset(%{user_id: barista.id, started_at: started_at})
        |> Repo.insert()

      create_paid_pos!(barista, DateTime.add(yesterday_end, -900, :second), "150")
      create_paid_pos!(barista, DateTime.add(today_start, 1800, :second), "360")

      {:ok, lv, _html} = live(conn, "/staff/close-my-shift")

      html = render(lv)
      assert html =~ "Orders completed"
      assert html =~ "Your sales today"
      assert html =~ "1"
      assert html =~ Menu.format_price(Decimal.new("360"))
      refute html =~ Menu.format_price(Decimal.new("510"))
      refute html =~ "2 orders"

      lv
      |> element("button", "End My Shift")
      |> render_click()

      lv
      |> element("button", "Yes, end my shift")
      |> render_click()

      assert is_nil(StaffShifts.get_open_shift(barista.id))

      html = render(lv)
      assert html =~ "Shift closed"
      assert html =~ Menu.format_price(Decimal.new("360"))
      refute html =~ Menu.format_price(Decimal.new("510"))
      refute html =~ "2 orders"

      closed_shift = Repo.get!(StaffShift, shift.id)
      refute is_nil(closed_shift.ended_at)
      assert DateTime.compare(today_end, closed_shift.ended_at) in [:gt, :eq]
    end

    test "shows duration on close", %{conn: conn, barista: barista} do
      {:ok, _shift} = StaffShifts.open_shift_for_login(barista)

      {:ok, lv, _html} = live(conn, "/staff/close-my-shift")

      # Close the shift
      lv
      |> element("button", "End My Shift")
      |> render_click()

      lv
      |> element("button", "Yes, end my shift")
      |> render_click()

      # Verify duration is shown
      html = render(lv)
      # Duration should be very small (< 1 minute) for this test
      assert html =~ "Duration:"
    end

    test "owner cannot access end my shift page", %{conn: _conn, owner: owner} do
      # Create a separate conn for the owner
      owner_conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, owner.id)

      {:ok, _shift} = StaffShifts.open_shift_for_login(owner)

      # Owner should not have access (only barista can access)
      # They'll be redirected by the guard
      owner_conn = get(owner_conn, "/staff/close-my-shift")
      assert redirected_to(owner_conn) == "/staff" || redirected_to(owner_conn) == "/"
    end

    test "can navigate back to home after closing", %{conn: conn, barista: barista} do
      {:ok, _shift} = StaffShifts.open_shift_for_login(barista)

      {:ok, lv, _html} = live(conn, "/staff/close-my-shift")

      # Close the shift
      lv
      |> element("button", "End My Shift")
      |> render_click()

      lv
      |> element("button", "Yes, end my shift")
      |> render_click()

      # Verify back to home button exists
      html = render(lv)
      assert html =~ "Back to Home"
      assert html =~ ~p"/staff"
    end
  end

  defp create_paid_pos!(user, settled_at, amount) do
    {:ok, order} =
      Orders.create_order([insert_pos_line!(amount)], %{
        customer_name: "Walk-in",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: "cash",
        source: :pos,
        settled_by_user_id: user.id,
        settlement_source: "pos"
      })

    Repo.update_all(
      from(o in Order, where: o.id == ^order.id),
      set: [settled_at: settled_at]
    )
  end

  defp insert_pos_line!(amount) do
    category =
      %Menu.Category{}
      |> Menu.Category.changeset(%{name: "Close-#{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    product =
      %Menu.Product{}
      |> Menu.Product.changeset(%{
        name: "Drink-#{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    price =
      %Menu.ProductPrice{}
      |> Menu.ProductPrice.changeset(%{
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
