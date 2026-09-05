defmodule Espreso.Printer do
  @moduledoc """
  Network ESC/POS client for the shop HS-802UL (port 9100).

  The Phoenix host must be on the **same LAN** as the printer
  (e.g. Mac on main Wi‑Fi during shop trial). Cloud hosts cannot
  reach `192.168.x.x` printers.
  """

  require Logger

  alias Espreso.Orders.Order
  alias Espreso.Printer.EscPos
  alias Espreso.Printer.Receipt

  @type result :: :ok | {:error, term()} | :disabled

  def config do
    Application.get_env(:espreso, __MODULE__, [])
  end

  def enabled? do
    conf = config()
    host = conf |> Keyword.get(:host) |> to_string() |> String.trim()

    Keyword.get(conf, :enabled, false) == true and host != ""
  end

  def host, do: config() |> Keyword.get(:host) |> to_string() |> String.trim()
  def port, do: Keyword.get(config(), :port, 9100)
  def timeout_ms, do: Keyword.get(config(), :timeout_ms, 4_000)

  @doc """
  After a successful cash-like payment: print receipt and open the drawer.
  """
  def after_cash_paid(%Order{} = order, opts \\ []) do
    with :ok <- print_receipt(order, opts),
         :ok <- open_drawer() do
      :ok
    end
  end

  @doc """
  After wallet / non-cash paid: print receipt only (no kaha).
  """
  def after_wallet_paid(%Order{} = order, opts \\ []), do: print_receipt(order, opts)

  @doc """
  Dispatches print/kick based on `paid_via`. Returns `:disabled` when printer is off.

  Options are forwarded to `Receipt.build/2` (e.g. `staff_name:`).
  """
  def after_paid(%Order{} = order, paid_via, opts \\ []) when is_binary(paid_via) do
    cond do
      not enabled?() ->
        :disabled

      cash_like?(paid_via) ->
        after_cash_paid(order, opts)

      true ->
        after_wallet_paid(order, opts)
    end
  end

  def print_receipt(%Order{} = order, opts \\ []) do
    send_bytes(Receipt.build(order, opts), "receipt #{order.number}")
  end

  def print_kitchen(%Order{} = order, opts \\ []) do
    send_bytes(Receipt.build_kitchen(order, opts), "kitchen #{order.number}")
  end

  def open_drawer(pin \\ :pin2) do
    bytes =
      case pin do
        :pin5 -> EscPos.drawer_kick_pin5()
        _ -> EscPos.drawer_kick_pin2()
      end

    send_bytes(bytes, "drawer #{pin}")
  end

  def test_print do
    bytes =
      EscPos.join([
        EscPos.init(),
        EscPos.align_center(),
        EscPos.bold_on(),
        EscPos.text_line("CoffeeSpot"),
        EscPos.bold_off(),
        EscPos.text_line("Espreso printer test"),
        EscPos.align_left(),
        EscPos.separator(),
        EscPos.text_line("Host: #{host()}"),
        EscPos.text_line(Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")),
        EscPos.separator(),
        EscPos.align_center(),
        EscPos.text_line("If you can read this,"),
        EscPos.text_line("staff printer works."),
        EscPos.feed(3),
        EscPos.cut()
      ])

    send_bytes(bytes, "test print")
  end

  def cash_like?("cash"), do: true
  def cash_like?("counter"), do: true
  def cash_like?(_), do: false

  def describe_result(:ok), do: "receipt printed"
  def describe_result(:disabled), do: nil
  def describe_result({:error, reason}), do: "print failed (#{inspect(reason)})"

  defp send_bytes(bytes, label) when is_binary(bytes) do
    if enabled?() do
      do_send(bytes, label)
    else
      :disabled
    end
  end

  defp do_send(bytes, label) do
    host = host()
    port = port()
    timeout = timeout_ms()

    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], timeout) do
      {:ok, socket} ->
        try do
          case :gen_tcp.send(socket, bytes) do
            :ok ->
              Process.sleep(150)
              Logger.info("printer #{label} ok → #{host}:#{port}")
              :ok

            {:error, reason} = err ->
              Logger.warning("printer #{label} send failed: #{inspect(reason)}")
              err
          end
        after
          :gen_tcp.close(socket)
        end

      {:error, reason} = err ->
        Logger.warning("printer #{label} connect failed #{host}:#{port}: #{inspect(reason)}")
        err
    end
  end
end
