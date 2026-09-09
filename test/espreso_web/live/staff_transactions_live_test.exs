defmodule EspresoWeb.StaffTransactionsLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Printer

  setup %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Mia Transactions",
        email: "transactions.mia@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Marco Manager",
        email: "transactions.manager@test.local",
        password: "password123",
        role: "manager"
      })

    %{conn: conn, barista: barista, manager: manager}
  end

  test "authenticated staff can browse, filter, and inspect today's receipts", %{
    conn: conn,
    barista: barista
  } do
    order = paid_order!("Daily Receipt", barista)
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/transactions")

    assert has_element?(view, "#staff-transactions")
    assert has_element?(view, "#staff-nav-transactions.is-active", "Transactions")
    assert has_element?(view, "#transactions-count", "1 paid transactions")
    refute has_element?(view, "#transactions-summary")
    assert has_element?(view, "#transaction-#{order.id}", order.number)

    view |> element("#transaction-#{order.id}") |> render_click()

    assert has_element?(view, "#transaction-detail", order.number)
    assert has_element?(view, "#transaction-detail", "Daily Receipt")
    assert has_element?(view, "#transaction-detail", "Mia Transactions")
    assert has_element?(view, "#transaction-detail", "Cash received")
    assert has_element?(view, "#transaction-detail", "₱100")
    assert has_element?(view, "#transaction-detail", "Change")
    assert has_element?(view, "#transaction-detail", "₱25")

    view
    |> form("#transactions-filters", %{"filters" => %{"payment" => "gcash"}})
    |> render_change()

    assert has_element?(view, "#transactions-empty", "No paid transactions found")
    refute has_element?(view, "#transaction-detail")
  end

  test "manager sees financial totals and payment breakdown", %{
    conn: conn,
    barista: barista,
    manager: manager
  } do
    paid_order!("Manager Receipt", barista)
    {:ok, view, _html} = live(log_in(conn, manager), ~p"/transactions")

    assert has_element?(view, "#transactions-summary", "₱75")
    assert has_element?(view, "#transactions-summary", "1 transactions")
    assert has_element?(view, "#transactions-breakdown", "Cash")
    assert has_element?(view, "#transactions-breakdown", "₱75")
  end

  test "reprint requires an explicit confirmation and cancellation sends nothing", %{
    conn: conn,
    barista: barista
  } do
    restore_printer_config_on_exit()
    Application.put_env(:espreso, Printer, enabled: true, host: "127.0.0.1", port: 1)

    order = paid_order!("Reprint Receipt", barista)
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/transactions")

    view |> element("#transaction-#{order.id}") |> render_click()
    assert has_element?(view, "#transaction-open-reprint", "Reprint receipt")

    view |> element("#transaction-open-reprint") |> render_click()

    assert has_element?(view, "#transaction-reprint-modal", order.number)
    assert has_element?(view, "#transaction-reprint-modal", "cash drawer will not open")
    assert has_element?(view, "#transaction-confirm-reprint", "Print receipt")

    view |> element("#transaction-cancel-reprint") |> render_click()
    refute has_element?(view, "#transaction-reprint-modal")
    refute has_element?(view, "#transactions-action-note", "Receipt sent")
  end

  test "confirmed history reprint sends one receipt without a drawer command", %{
    conn: conn,
    barista: barista
  } do
    restore_printer_config_on_exit()
    {port, printer_task} = start_test_printer!()
    Application.put_env(:espreso, Printer, enabled: true, host: "127.0.0.1", port: port)

    order = paid_order!("Confirmed Reprint", barista)
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/transactions")

    view |> element("#transaction-#{order.id}") |> render_click()
    view |> element("#transaction-open-reprint") |> render_click()
    view |> element("#transaction-confirm-reprint") |> render_click()

    assert has_element?(view, "#transactions-action-note", "Receipt sent to printer")
    refute has_element?(view, "#transaction-reprint-modal")

    receipt = Task.await(printer_task, 2_000)
    assert receipt =~ order.number
    assert :binary.match(receipt, <<0x1B, 0x70>>) == :nomatch
  end

  test "guest cannot access transaction history", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/transactions")
  end

  defp paid_order!(customer_name, cashier) do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: customer_name,
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          settlement_source: "pos",
          settled_by_user_id: cashier.id,
          cash_tendered: Decimal.new("100")
        }
      )

    order
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp restore_printer_config_on_exit do
    original = Application.get_env(:espreso, Printer)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:espreso, Printer)
      else
        Application.put_env(:espreso, Printer, original)
      end
    end)
  end

  defp start_test_printer! do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 1_500)
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 1_500)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        bytes
      end)

    {port, task}
  end
end
