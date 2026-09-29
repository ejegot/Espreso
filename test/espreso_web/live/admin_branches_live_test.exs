defmodule EspresoWeb.AdminBranchesLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu
  alias Espreso.Tenancy
  alias Espreso.Tenancy.Branches

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.branches@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Barista",
        email: "barista.branches@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, barista: barista}
  end

  test "owner can add a CoffeeSpot branch", %{conn: conn, owner: owner} do
    {:ok, view, html} = live(log_in(conn, owner), ~p"/admin/branches")

    assert html =~ "Lilac"
    assert has_element?(view, "#admin-branch-form")

    view
    |> form("#admin-branch-form", branch: %{name: "Ortigas", address: "Ortigas Ave"})
    |> render_submit()

    html = render(view)
    assert html =~ "Ortigas"
    assert html =~ "/b/ortigas/menu"

    branch = Tenancy.get_branch_by_slug(owner.tenant_id, "ortigas")
    assert branch
    refute branch.main
    assert Branches.guest_menu_path(branch) == "/b/ortigas/menu"
  end

  test "barista cannot open branches", %{conn: conn, barista: barista} do
    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, barista), ~p"/admin/branches")
  end

  test "guest menu slug is isolated from Lilac catalog", %{owner: owner} do
    {:ok, branch} = Branches.create_as(owner, %{name: "Katipunan", address: "Katipunan Ave"})

    Tenancy.put_context(%{tenant_id: branch.tenant_id, branch_id: branch.id})
    assert Menu.list_menu() == []

    Tenancy.put_lilac_context()
  end

  test "unknown guest slug redirects to Lilac menu", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/menu"}}} = live(conn, ~p"/b/not-a-shop/menu")
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:branch_id, user.branch_id)
  end
end
