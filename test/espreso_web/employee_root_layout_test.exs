defmodule EspresoWeb.EmployeeRootLayoutTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Orders

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Layout Owner",
        email: "layout.owner@test.local",
        password: "password123",
        role: "owner"
      })

    %{owner: owner}
  end

  test "employee authentication pages use the Elilai Kafe root", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/login")

    assert html =~ ~s(data-application="elilai-kafe-employee")
    assert html =~ ~s(class="site-body elilai-kafe-employee-root")
    assert html =~ ~s(rel="manifest")
    assert html =~ ~s(href="/elilai-kafe.webmanifest")
    assert html =~ ~s(name="theme-color" content="#394331")
    assert html =~ ~s(rel="apple-touch-icon")
    assert html =~ ~s(href="/images/elilai-kafe/apple-touch-icon.png")
    assert html =~ ~s(name="apple-mobile-web-app-title")

    # Employee login fonts: DM Sans + Instrument Serif only (not Fraunces/Figtree).
    assert html =~ "family=DM+Sans"
    assert html =~ "family=Instrument+Serif"
    refute html =~ "family=Fraunces"
    refute html =~ "family=Figtree"

    assert has_element?(view, "img.staff-auth-logo")
    assert html =~ "/images/elilai-kafe/elilai-kafe-mark.png"
    assert has_element?(
             view,
             "aside.staff-auth-visual source[type='image/webp'][srcset='/images/elilai-kafe/login-brand-panel.webp']"
           )

    assert has_element?(view, "h1.staff-auth-title")

    assert {:error, {:live_redirect, %{to: "/login"}}} = live(recycle(conn), ~p"/register")
  end

  test "every protected employee page uses the employee root and branded staff shell", %{
    conn: conn,
    owner: owner
  } do
    paths = [
      ~p"/staff",
      ~p"/orders",
      ~p"/pos",
      ~p"/transactions",
      ~p"/dashboard",
      ~p"/staff/close",
      ~p"/admin/availability",
      ~p"/admin/users",
      ~p"/admin/settings"
    ]

    for path <- paths do
      {:ok, view, html} = live(log_in(recycle(conn), owner), path)

      assert html =~ ~s(data-application="elilai-kafe-employee")
      assert html =~ ~s(class="site-body elilai-kafe-employee-root")
      assert html =~ ~s(href="/elilai-kafe.webmanifest")
      assert html =~ ~s(href="/images/elilai-kafe/apple-touch-icon.png")

      if path == ~p"/pos" do
        assert has_element?(
                 view,
                 "#staff-pos-rail img.staff-pos-rail-logo[src='/images/elilai-kafe/elilai-kafe-logo.png']"
               )
      else
        if path == ~p"/orders" do
          assert has_element?(view, "#staff-shell .staff-shell-brand-label", "Elilai Kafe")
          refute has_element?(view, "#staff-shell img.staff-shell-brand-logo")
        else
          assert has_element?(
                   view,
                   "#staff-shell img.staff-shell-brand-logo[src='/images/elilai-kafe/elilai-kafe-logo.jpg']"
                 )
        end
      end
    end
  end

  test "customer pages keep the customer root", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Root Check", fulfillment: :pickup, payment_method: :counter}
      )

    paths = [
      ~p"/",
      ~p"/menu",
      ~p"/order/#{order.number}",
      ~p"/about",
      ~p"/contact"
    ]

    for path <- paths do
      {:ok, _view, html} = live(recycle(conn), path)

      refute html =~ ~s(data-application="elilai-kafe-employee")
      refute html =~ "elilai-kafe-employee-root"
      refute html =~ "/elilai-kafe.webmanifest"
      refute html =~ ~s(name="apple-mobile-web-app-title")
      refute html =~ "/images/elilai-kafe/apple-touch-icon.png"
      refute html =~ "/images/elilai-kafe/elilai-kafe-logo.jpg"
    end
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
