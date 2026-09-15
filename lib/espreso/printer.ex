defmodule Espreso.Printer do
  @moduledoc """
  ESC/POS receipt/drawer helpers for the shop HS-802UL.

  Transports:
  - `:lan_server` — Phoenix opens TCP to the printer (same LAN trial only)
  - `:native_client` — Phoenix builds bytes; ELIlai Kafe Android sends via Capacitor
  - `:off` — printing disabled

  Fly/cloud must use `:native_client` (or `:off`). Never point Fly at `192.168.x.x`.
  """

  require Logger

  alias Espreso.Orders.Order
  alias Espreso.Printer.EscPos
  alias Espreso.Printer.Receipt

  @type transport :: :off | :lan_server | :native_client
  @type result :: :ok | {:error, term()} | :disabled
  @type dispatch_result ::
          :dispatched
          | :disabled
          | {:definite_failure, term()}
          | {:uncertain, term()}
          | {:client_dispatch, binary()}

  def config do
    Application.get_env(:espreso, __MODULE__, [])
  end

  def transport do
    case Keyword.get(config(), :transport, :off) do
      value when value in [:off, :lan_server, :native_client] -> value
      "off" -> :off
      "lan_server" -> :lan_server
      "native_client" -> :native_client
      "client" -> :native_client
      _ -> :off
    end
  end

  def enabled? do
    conf = config()

    case transport() do
      :off ->
        false

      :native_client ->
        Keyword.get(conf, :enabled, false) == true

      :lan_server ->
        host = conf |> Keyword.get(:host) |> to_string() |> String.trim()
        Keyword.get(conf, :enabled, false) == true and host != ""
    end
  end

  def native_client?, do: transport() == :native_client
  def lan_server?, do: transport() == :lan_server

  def host, do: config() |> Keyword.get(:host) |> to_string() |> String.trim()
  def port, do: Keyword.get(config(), :port, 9100)
  def timeout_ms, do: Keyword.get(config(), :timeout_ms, 4_000)

  @doc """
  After a successful cash-like payment: print receipt and open the drawer.

  Only valid for `:lan_server`. Prefer coordinator + client bridge in production.
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

      native_client?() ->
        {:error, :use_client_bridge}

      cash_like?(paid_via) ->
        after_cash_paid(order, opts)

      true ->
        after_wallet_paid(order, opts)
    end
  end

  def print_receipt(%Order{} = order, opts \\ []) do
    send_bytes(Receipt.build(order, opts), "receipt #{order.number}")
  end

  @doc """
  Dispatches receipt bytes with transport-phase result semantics.

  A successful TCP send / client handoff means the command was dispatched, not that
  paper output was physically confirmed by the printer.
  """
  def dispatch_receipt(%Order{} = order, opts \\ []) do
    Receipt.build(order, opts)
    |> dispatch_payload("receipt #{order.number}")
  end

  def print_kitchen(%Order{} = order, opts \\ []) do
    send_bytes(Receipt.build_kitchen(order, opts), "kitchen #{order.number}")
  end

  def dispatch_kitchen(%Order{} = order, opts \\ []) do
    Receipt.build_kitchen(order, opts)
    |> dispatch_payload("kitchen #{order.number}")
  end

  def open_drawer(pin \\ :pin2) do
    send_bytes(drawer_bytes(pin), "drawer #{pin}")
  end

  def dispatch_drawer(pin \\ :pin2) do
    drawer_bytes(pin)
    |> dispatch_payload("drawer #{pin}")
  end

  def drawer_bytes(pin \\ :pin2) do
    case pin do
      :pin5 -> EscPos.drawer_kick_pin5()
      _ -> EscPos.drawer_kick_pin2()
    end
  end

  def encode_payload(bytes) when is_binary(bytes), do: Base.encode64(bytes)

  def test_print_bytes do
    EscPos.join([
      EscPos.init(),
      EscPos.align_center(),
      EscPos.bold_on(),
      EscPos.text_line("CoffeeSpot"),
      EscPos.bold_off(),
      EscPos.text_line("Espreso printer test"),
      EscPos.align_left(),
      EscPos.separator(),
      EscPos.text_line("Transport: #{transport()}"),
      EscPos.text_line(Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")),
      EscPos.separator(),
      EscPos.align_center(),
      EscPos.text_line("If you can read this,"),
      EscPos.text_line("staff printer works."),
      EscPos.feed(3),
      EscPos.cut()
    ])
  end

  def test_print do
    send_bytes(test_print_bytes(), "test print")
  end

  def dispatch_payload_test do
    dispatch_payload(test_print_bytes(), "test print")
  end

  def cash_like?("cash"), do: true
  def cash_like?("counter"), do: true
  def cash_like?(_), do: false

  def describe_result(:ok), do: "receipt printed"
  def describe_result(:disabled), do: nil
  def describe_result({:error, reason}), do: "print failed (#{inspect(reason)})"

  defp dispatch_payload(bytes, label) when is_binary(bytes) do
    case transport() do
      :native_client ->
        if enabled?() do
          {:client_dispatch, bytes}
        else
          :disabled
        end

      :lan_server ->
        send_bytes_detailed(bytes, label) |> dispatch_result()

      :off ->
        :disabled
    end
  end

  defp send_bytes(bytes, label) when is_binary(bytes) do
    case transport() do
      :native_client ->
        {:error, :use_client_bridge}

      :off ->
        :disabled

      :lan_server ->
        case send_bytes_detailed(bytes, label) do
          :ok -> :ok
          :disabled -> :disabled
          {:error, _phase, reason} -> {:error, reason}
        end
    end
  end

  defp send_bytes_detailed(bytes, label) when is_binary(bytes) do
    if lan_server?() and enabled?() do
      do_send(bytes, label)
    else
      :disabled
    end
  end

  defp dispatch_result(:ok), do: :dispatched
  defp dispatch_result(:disabled), do: :disabled
  defp dispatch_result({:error, :connect, reason}), do: {:definite_failure, reason}
  defp dispatch_result({:error, :send, reason}), do: {:uncertain, reason}

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

            {:error, reason} ->
              Logger.warning("printer #{label} send failed: #{inspect(reason)}")
              {:error, :send, reason}
          end
        after
          :gen_tcp.close(socket)
        end

      {:error, reason} ->
        Logger.warning("printer #{label} connect failed #{host}:#{port}: #{inspect(reason)}")
        {:error, :connect, reason}
    end
  end
end
