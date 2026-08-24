defmodule EspresoWeb.AdminSettingsLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.BusinessSettings

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.adminsettings@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager.adminsettings@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Staff",
        email: "staff.adminsettings@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, manager: manager, barista: barista}
  end

  test "owner can access settings and see current values", %{conn: conn, owner: owner} do
    settings = BusinessSettings.get()
    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/settings")

    assert has_element?(view, ".staff-orders-title", "Business settings")
    assert has_element?(view, "#admin-settings-form")
    assert has_element?(view, "#admin-settings-form input[name='settings[business_name]']")

    html = render(view)
    assert html =~ settings.business_name
    assert html =~ settings.address
    assert html =~ settings.phone
    assert html =~ settings.email
    assert html =~ hd(settings.hours_lines)
    assert html =~ settings.instagram_url
  end

  test "manager and staff are denied", %{conn: conn, manager: manager, barista: barista} do
    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, manager), ~p"/admin/settings")

    assert {:error, {:redirect, %{to: "/staff"}}} =
             live(log_in(conn, barista), ~p"/admin/settings")
  end

  test "owner can save settings and see success feedback", %{conn: conn, owner: owner} do
    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/settings")

    view
    |> form("#admin-settings-form", %{
      settings: %{
        business_name: "CoffeeSpot Updated",
        address: "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
        phone: "+639566728906",
        email: "updated@coffeespot.local",
        hours_text: "Mon–Sun · 9:00 AM – 9:00 PM\nHoliday hours on Instagram",
        instagram_url: "https://www.instagram.com/coffeespot_lilac.marikina/",
        facebook_url: "https://www.facebook.com/profile.php?id=61572602608495",
        tiktok_url: "https://www.tiktok.com/@coffeespotlilac_"
      }
    })
    |> render_submit()

    assert has_element?(view, "#settings-flash", "Business settings saved.")
    html = render(view)
    assert html =~ "CoffeeSpot Updated"
    assert html =~ "updated@coffeespot.local"
    assert html =~ "Mon–Sun · 9:00 AM – 9:00 PM"

    saved = BusinessSettings.get()
    assert saved.business_name == "CoffeeSpot Updated"
    assert saved.email == "updated@coffeespot.local"
    assert saved.hours_lines == ["Mon–Sun · 9:00 AM – 9:00 PM", "Holiday hours on Instagram"]
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
