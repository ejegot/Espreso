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

  test "employee authentication pages use the ELIlai Kafe root", %{conn: conn} do
    for path <- [~p"/login", ~p"/register"] do
      {:ok, view, html} = live(recycle(conn), path)

      assert html =~ ~s(data-application="elilai-kafe-employee")
      assert html =~ ~s(class="site-body elilai-kafe-employee-root")
      assert has_element?(view, ".staff-auth-brand-name", "ELIlai Kafe")
    end
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

      if path == ~p"/pos" do
        assert has_element?(view, "#staff-pos-rail .staff-pos-rail-wordmark", "ELIlai Kafe")
      else
        assert has_element?(view, "#staff-shell .staff-shell-brand", "ELIlai Kafe")
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
    end
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
