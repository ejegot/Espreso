defmodule EspresoWeb.StaffHomePrinterTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Printer

  setup do
    original_config = Application.get_env(:espreso, Printer)

    Application.put_env(:espreso, Printer,
      enabled: true,
      transport: :native_client,
      host: nil,
      port: 9100,
      timeout_ms: 1_000
    )

    on_exit(fn ->
      Application.put_env(:espreso, Printer, original_config)
    end)

    :ok
  end

  test "printer controls appear on Home for owner, manager, and staff", %{conn: conn} do
    for role <- ["owner", "manager", "barista"] do
      user = register_user!(role)
      {:ok, view, html} = live(home_conn(conn, user), ~p"/staff")

      assert has_element?(view, "#staff-home-printer", "Printer & cash drawer")
      assert has_element?(view, "#staff-printer-test", "Test print")
      assert has_element?(view, "#staff-printer-drawer", "Test Drawer")

      if role == "owner" do
        assert :binary.match(html, "owner-home-boards") <
                 :binary.match(html, "staff-home-printer")
      end
    end
  end

  test "printer controls show dispatch and device-result feedback", %{conn: conn} do
    user = register_user!("barista")
    {:ok, view, _html} = live(home_conn(conn, user), ~p"/staff")

    view |> element("#staff-printer-test") |> render_click()
    assert_push_event(view, "elilai-printer", %{action: "raw_test", flow: "raw_test"})
    assert has_element?(view, "#staff-printer-note", "Sending test print")

    render_hook(view, "elilai_printer_result", %{"flow" => "raw_test", "ok" => true})
    assert has_element?(view, "#staff-printer-note", "Test print: ok")

    view |> element("#staff-printer-drawer") |> render_click()
    assert_push_event(view, "elilai-printer", %{action: "raw_drawer", flow: "raw_drawer"})
    assert has_element?(view, "#staff-printer-note", "Test Drawer")

    render_hook(view, "elilai_printer_result", %{"flow" => "raw_drawer", "ok" => true})
    assert has_element?(view, "#staff-printer-note", "Test Drawer: ok")
  end

  test "printer controls stay hidden when the printer is disabled", %{conn: conn} do
    Application.put_env(:espreso, Printer,
      enabled: false,
      transport: :native_client,
      host: nil,
      port: 9100,
      timeout_ms: 1_000
    )

    user = register_user!("owner")
    {:ok, view, _html} = live(home_conn(conn, user), ~p"/staff")

    refute has_element?(view, "#staff-home-printer")
  end

  defp register_user!(role) do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Printer #{role}",
        email: "printer-#{role}-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: role
      })

    user
  end

  defp home_conn(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
