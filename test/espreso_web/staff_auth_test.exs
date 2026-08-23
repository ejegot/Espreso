defmodule EspresoWeb.StaffAuthTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Staff",
        email: "barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, manager: manager, barista: barista}
  end

  test "staff home and orders require login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/staff")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orders")
  end

  test "login lands on staff home", %{conn: conn, barista: barista} do
    {:ok, _view, html} = live(conn, ~p"/login")
    assert html =~ "Hello, welcome back"

    conn =
      post(conn, ~p"/session", %{
        "user" => %{"email" => barista.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/staff"
    assert get_session(conn, :user_id) == barista.id
  end

  test "anyone can open register and sign-in link is present", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/register")
    assert html =~ "Create your account"
    assert has_element?(view, "#staff-register-form")
    assert has_element?(view, "a[href='/login']", "Sign In")
    assert html =~ "Already have an account?"
  end

  test "self-register creates staff then can login", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    {:ok, conn} =
      view
      |> form("#staff-register-form", %{
        user: %{
          name: "New Staff",
          email: "newstaff@test.local",
          password: "password123",
          role: "barista"
        }
      })
      |> render_submit()
      |> follow_redirect(conn, ~p"/login")

    html = html_response(conn, 200)
    assert html =~ "Hello, welcome back"
    assert html =~ "Account created"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => "newstaff@test.local", "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/staff"
  end

  test "staff home shows Orders and POS, not Staff accounts", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/staff")

    assert has_element?(view, ".staff-orders-title", "Home")
    assert has_element?(view, "a[href='/orders']", "Orders")
    assert has_element?(view, "a[href='/pos']", "POS")
    refute has_element?(view, "a[href='/admin/users']", "Staff accounts")
  end

  test "manager can access staff routes but not user management", %{
    conn: conn,
    manager: manager
  } do
    conn = log_in(conn, manager)

    {:ok, home, _html} = live(conn, ~p"/staff")
    assert has_element?(home, "a[href='/orders']", "Orders")
    refute has_element?(home, "a[href='/admin/users']", "Staff accounts")

    {:ok, orders, _html} = live(conn, ~p"/orders")
    assert has_element?(orders, ".staff-orders-title")

    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/admin/users")
  end

  test "owner staff home shows Staff accounts", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/staff")
    assert has_element?(view, "a[href='/admin/users']", "Staff accounts")

    {:ok, admin, _html} = live(conn, ~p"/admin/users")
    assert has_element?(admin, ".staff-orders-title", "Staff users")
  end

  test "staff cannot open admin users", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/admin/users")
  end

  test "owner cannot edit own role in admin UI", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/admin/users")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{owner.id}"]))
    |> render_click()

    refute has_element?(view, "#edit-user-#{owner.id} select[name='user[role]']")
    assert has_element?(view, "#edit-user-#{owner.id}")
  end

  test "pos placeholder is reachable for staff", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/pos")
    assert has_element?(view, ".staff-orders-title", "POS")
    assert render(view) =~ "Coming soon"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
