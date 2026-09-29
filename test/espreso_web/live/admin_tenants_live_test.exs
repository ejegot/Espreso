defmodule EspresoWeb.AdminTenantsLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Marketing
  alias Espreso.Menu
  alias Espreso.Repo
  alias Espreso.Tenancy
  alias Espreso.Tenancy.Tenants

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.tenants@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Barista",
        email: "barista.tenants@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, barista: barista}
  end

  test "CoffeeSpot owner can add a tenant", %{conn: conn, owner: owner} do
    {:ok, view, html} = live(log_in(conn, owner), ~p"/admin/tenants")

    assert html =~ "CoffeeSpot"
    assert has_element?(view, "#admin-tenant-form")

    view
    |> form("#admin-tenant-form",
      tenant: %{
        name: "Kape ni Juan",
        owner_name: "Juan dela Cruz",
        address: "Quezon City",
        pin: "2468",
        pin_confirmation: "2468"
      }
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Kape ni Juan"
    assert html =~ "/t/kape-ni-juan/menu"
    assert html =~ "/t/kape-ni-juan/login"

    tenant = Tenancy.get_tenant_by_slug("kape-ni-juan")
    assert tenant
    refute Tenancy.coffeespot_tenant?(tenant.id)
  end

  test "barista cannot open tenants", %{conn: conn, barista: barista} do
    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, barista), ~p"/admin/tenants")
  end

  test "renter owner cannot open tenants", %{conn: conn, owner: owner} do
    {:ok, %{owner: renter}} =
      Tenants.create_as(owner, %{
        name: "Solo Cafe",
        owner_name: "Solo",
        pin: "9999"
      })

    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, renter), ~p"/admin/tenants")
  end

  test "guest tenant menu is isolated from Lilac catalog", %{conn: conn, owner: owner} do
    {:ok, %{tenant: tenant, branch: branch}} =
      Tenants.create_as(owner, %{
        name: "Isolated Cafe",
        owner_name: "Isa",
        pin: "4321"
      })

    Tenancy.put_context(%{tenant_id: tenant.id, branch_id: branch.id})
    assert Menu.list_menu() == []
    Tenancy.put_lilac_context()

    {:ok, _view, html} = live(conn, ~p"/t/isolated-cafe/menu")
    assert html =~ "Isolated Cafe"
    assert html =~ "Visit Isolated Cafe"
    refute html =~ "Pure Tableya"
    refute html =~ "Come say hi in Lilac"
    refute html =~ "Students: Free size upgrade"

    {:ok, _view, cs_html} = live(conn, ~p"/menu")
    assert cs_html =~ "Pure Tableya"
    assert cs_html =~ "Visit CoffeeSpot"

    assert {:error, {:redirect, %{to: "/menu"}}} = live(conn, ~p"/t/not-a-cafe/menu")
  end

  test "PIN roster is per tenant", %{conn: conn, owner: owner} do
    {:ok, %{tenant: tenant}} =
      Tenants.create_as(owner, %{
        name: "Roster Cafe",
        owner_name: "Roster Owner",
        pin: "5555"
      })

    {:ok, _view, html} = live(conn, ~p"/login")
    refute html =~ "Roster Owner"

    {:ok, view, _html} = live(conn, ~p"/t/#{tenant.slug}/login")
    html = render_click(view, "open_roster")
    assert html =~ "Roster Owner"
  end

  test "waitlist request can be opened into a tenant", %{conn: conn, owner: owner} do
    {:ok, request} =
      Marketing.create_shop_request(%{
        "contact_name" => "Ana Cruz",
        "cafe_name" => "Lilac Brew Waitlist",
        "city" => "Marikina",
        "email" => "ana.waitlist@cafe.ph",
        "mobile" => "09171234567",
        "note" => "Two counters"
      })

    {:ok, view, html} = live(log_in(conn, owner), ~p"/admin/tenants")
    assert html =~ "Lilac Brew Waitlist"
    assert has_element?(view, "#waitlist-open-#{request.id}")

    view |> element("#waitlist-open-#{request.id}") |> render_click()
    html = render(view)
    assert html =~ "Waitlist: Lilac Brew Waitlist"

    view
    |> form("#admin-tenant-form",
      tenant: %{
        pin: "2468",
        pin_confirmation: "2468"
      }
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Lilac Brew Waitlist is ready"
    assert html =~ "/t/lilac-brew-waitlist/menu"
    refute has_element?(view, "#waitlist-row-#{request.id}")

    request = Repo.reload!(request)
    assert request.status == "opened"
    assert request.tenant_id
  end

  test "waitlist request can be dismissed", %{conn: conn, owner: owner} do
    {:ok, request} =
      Marketing.create_shop_request(%{
        "contact_name" => "Ben",
        "cafe_name" => "Skip Cafe",
        "city" => "Pasig",
        "email" => "ben@skip.ph",
        "mobile" => "09180001111"
      })

    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/tenants")
    view |> element("#waitlist-dismiss-#{request.id}") |> render_click()

    refute has_element?(view, "#waitlist-row-#{request.id}")
    assert Repo.reload!(request).status == "dismissed"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:branch_id, user.branch_id)
  end
end
