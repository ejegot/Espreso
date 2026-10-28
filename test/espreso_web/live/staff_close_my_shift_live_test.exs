defmodule EspresoWeb.StaffCloseMyShiftLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Espreso.Accounts
  alias Espreso.StaffShifts

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

  describe "close my shift" do
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
      |> element("button", "Close my shift")
      |> render_click()

      # Verify button changes to confirmation
      html = render(lv)
      assert html =~ "Yes, close my shift"

      # Click confirmation
      lv
      |> element("button", "Yes, close my shift")
      |> render_click()

      # Verify shift is closed in database
      closed_shift = StaffShifts.get_open_shift(barista.id)
      assert is_nil(closed_shift), "Shift should be closed"

      # Verify the UI shows shift closed with sales
      html = render(lv)
      assert html =~ "Shift closed"
      assert html =~ "Your sales"
    end

    test "shows duration on close", %{conn: conn, barista: barista} do
      {:ok, _shift} = StaffShifts.open_shift_for_login(barista)

      {:ok, lv, _html} = live(conn, "/staff/close-my-shift")

      # Close the shift
      lv
      |> element("button", "Close my shift")
      |> render_click()

      lv
      |> element("button", "Yes, close my shift")
      |> render_click()

      # Verify duration is shown
      html = render(lv)
      # Duration should be very small (< 1 minute) for this test
      assert html =~ "Duration:"
    end

    test "owner cannot access close my shift page", %{conn: _conn, owner: owner} do
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
      |> element("button", "Close my shift")
      |> render_click()

      lv
      |> element("button", "Yes, close my shift")
      |> render_click()

      # Verify back to home button exists
      html = render(lv)
      assert html =~ "Back to Home"
      assert html =~ ~p"/staff"
    end
  end
end
