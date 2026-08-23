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

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Barista",
        email: "barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, barista: barista}
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

  test "barista staff home shows Orders and POS, not Staff accounts", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/staff")

    assert has_element?(view, ".staff-orders-title", "Home")
    assert has_element?(view, "a[href='/orders']", "Orders")
    assert has_element?(view, "a[href='/pos']", "POS")
    refute has_element?(view, "a[href='/admin/users']", "Staff accounts")
  end

  test "owner staff home shows Staff accounts", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/staff")
    assert has_element?(view, "a[href='/admin/users']", "Staff accounts")

    {:ok, admin, _html} = live(conn, ~p"/admin/users")
    assert has_element?(admin, ".staff-orders-title", "Staff users")
  end

  test "barista cannot open admin users", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/admin/users")
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
