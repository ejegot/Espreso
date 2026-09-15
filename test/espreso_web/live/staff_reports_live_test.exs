defmodule EspresoWeb.StaffReportsLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo

  import Ecto.Query

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Reports Owner",
        email: "reports.owner@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Reports Manager",
        email: "reports.manager@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Reports Barista",
        email: "reports.barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, manager: manager, barista: barista}
  end

  test "owner and manager can open Sales Report; barista cannot", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff/reports")
    assert has_element?(owner_view, "#staff-reports")
    assert has_element?(owner_view, "#staff-reports-from")
    assert has_element?(owner_view, "#staff-reports-to")
    assert has_element?(owner_view, "#staff-reports-export", "Export Excel")
    assert has_element?(owner_view, "#staff-nav-reports")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff/reports")
    assert has_element?(manager_view, "#staff-reports-export", "Export Excel")

    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, barista), ~p"/staff/reports")
  end

  test "rejects ranges longer than 31 days in the form", %{conn: conn, owner: owner} do
    {:ok, view, _html} = live(log_in(conn, owner), ~p"/staff/reports")

    view
    |> form("#staff-reports-export-form", %{
      report: %{from: "2026-09-01", to: "2026-10-02"}
    })
    |> render_change()

    assert has_element?(
             view,
             "#staff-reports-error",
             "Choose a date range of #{Orders.max_sales_export_shop_days()} days or fewer."
           )
  end

  test "owner can download xlsx for a valid range", %{conn: conn, owner: owner} do
    create_paid!(owner, settled_at: ~U[2026-09-10 02:00:00Z], price: "120")

    conn = log_in(conn, owner)

    conn =
      get(conn, ~p"/staff/reports/export", %{
        "from" => "2026-09-10",
        "to" => "2026-09-10"
      })

    assert conn.status == 200

    content_type =
      conn
      |> get_resp_header("content-type")
      |> List.first()

    assert content_type =~ "spreadsheetml" or content_type =~ "xlsx"

    disposition =
      conn
      |> get_resp_header("content-disposition")
      |> List.first()

    assert disposition =~ "elilai-sales-2026-09-10-2026-09-10.xlsx"

    body = response(conn, 200)
    assert is_binary(body)
    assert String.starts_with?(body, "PK")
  end

  test "manager can download xlsx; barista cannot", %{
    conn: conn,
    manager: manager,
    barista: barista
  } do
    manager_conn =
      log_in(conn, manager)
      |> get(~p"/staff/reports/export", %{"from" => "2026-09-10", "to" => "2026-09-10"})

    assert response(manager_conn, 200)
    assert String.starts_with?(manager_conn.resp_body, "PK")

    barista_conn =
      log_in(conn, barista)
      |> get(~p"/staff/reports/export", %{"from" => "2026-09-10", "to" => "2026-09-10"})

    assert redirected_to(barista_conn) == ~p"/staff"
  end

  test "export rejects oversized range", %{conn: conn, owner: owner} do
    conn =
      log_in(conn, owner)
      |> get(~p"/staff/reports/export", %{"from" => "2026-09-01", "to" => "2026-10-02"})

    assert redirected_to(conn) == ~p"/staff/reports"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "31 days"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp create_paid!(user, opts) do
    settled_at = Keyword.fetch!(opts, :settled_at)
    price = Keyword.get(opts, :price, "100")

    category =
      %Espreso.Menu.Category{}
      |> Espreso.Menu.Category.changeset(%{
        name: "DlCat-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    product =
      %Espreso.Menu.Product{}
      |> Espreso.Menu.Product.changeset(%{
        name: "Espresso-#{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    product_price =
      %Espreso.Menu.ProductPrice{}
      |> Espreso.Menu.ProductPrice.changeset(%{
        product_id: product.id,
        size: nil,
        price: Decimal.new(price)
      })
      |> Repo.insert!()

    {:ok, order} =
      Orders.create_order(
        [
          %{
            product_id: product.id,
            price_id: product_price.id,
            name: product.name,
            size: nil,
            quantity: 1,
            price: product_price.price
          }
        ],
        %{
          customer_name: "Download Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          source: :pos,
          settlement_source: :pos,
          settled_by_user_id: user.id
        }
      )

    {1, _} =
      Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [settled_at: settled_at])

    order
  end
end
