defmodule EspresoWeb.StaffOwnerSetupLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts

  test "empty system shows Initial Owner Setup from /setup and /login", %{conn: conn} do
    assert Accounts.needs_initial_owner_setup?()

    assert {:error, {:live_redirect, %{to: "/setup"}}} = live(conn, ~p"/login")

    {:ok, view, html} = live(conn, ~p"/setup")
    assert html =~ "Owner setup"
    assert has_element?(view, "#owner-setup-form")
    assert has_element?(view, "#owner-setup-name")
    assert has_element?(view, "#owner-setup-pin")
    assert has_element?(view, "#owner-setup-pin-confirmation")
    refute html =~ ~r/type=\"email\"/i
    refute html =~ "Password"
  end

  test "successful setup creates owner session and lands on staff home", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    {:ok, conn} =
      view
      |> form("#owner-setup-form", %{
        setup: %{name: "Shop Owner", pin: "1357", pin_confirmation: "1357"}
      })
      |> render_submit()
      |> follow_redirect(conn)

    assert conn.request_path =~ "/session/token/"
    assert redirected_to(conn) == ~p"/staff"
    assert get_session(conn, :user_id)

    owner = Accounts.get_user!(get_session(conn, :user_id))
    assert owner.role == "owner"
    assert owner.name == "Shop Owner"
    assert {:ok, _} = Accounts.verify_pin(owner.id, "1357")

    {:ok, _home, home_html} = live(conn, ~p"/staff")
    assert home_html =~ "Shop Owner" or home_html =~ "Home" or home_html =~ "staff"
  end

  test "PIN mismatch and invalid format are rejected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    html =
      view
      |> form("#owner-setup-form", %{
        setup: %{name: "Owner", pin: "1357", pin_confirmation: "9999"}
      })
      |> render_submit()

    assert html =~ "PINs do not match"
    assert Accounts.first_user?()

    html =
      view
      |> form("#owner-setup-form", %{
        setup: %{name: "Owner", pin: "12", pin_confirmation: "12"}
      })
      |> render_submit()

    assert html =~ "PIN must be 4–6 digits"
    assert Accounts.first_user?()
  end

  test "/register redirects to setup when uninitialized and to login after", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/setup"}}} = live(conn, ~p"/register")

    assert {:ok, _} =
             Accounts.bootstrap_initial_owner(%{
               name: "Owner",
               pin: "2468",
               pin_confirmation: "2468"
             })

    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/register")
  end

  test "login has no Register CTA after initialization", %{conn: conn} do
    assert {:ok, owner} =
             Accounts.bootstrap_initial_owner(%{
               name: "Owner",
               pin: "2468",
               pin_confirmation: "2468"
             })

    assert {:ok, _} = Accounts.set_pin(owner, "2468")

    {:ok, view, html} = live(conn, ~p"/login")
    refute has_element?(view, ".staff-auth-register")
    refute html =~ "Need an account?"
    refute html =~ ~r/href=\"\/register\"/
  end
end
