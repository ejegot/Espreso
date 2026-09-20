defmodule Espreso.CustomerPush do
  @moduledoc """
  Web Push for QR (customer-source) orders: Preparing and Ready only.

  Sending is best-effort and must not fail kitchen status updates.
  """

  import Ecto.Query

  alias Espreso.CustomerPush.Subscription
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias EspresoWeb.Endpoint

  @notify_statuses ~w(preparing ready)
  @prompt_statuses ~w(received preparing ready)
  @ttl_hours 4

  def enabled? do
    match?({:ok, _}, vapid_public_key()) and match?({:ok, _}, vapid_private_key())
  end

  def vapid_public_key do
    case vapid_config()[:public_key] do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> :error
    end
  end

  def vapid_public_key_js do
    case vapid_public_key() do
      {:ok, key} -> key
      :error -> ""
    end
  end

  def promptable?(%Order{} = order) do
    enabled?() and
      order.source == "customer" and
      order.status in @prompt_statuses
  end

  def promptable?(_), do: false

  def subscribe(%Order{} = order, attrs) when is_map(attrs) do
    cond do
      not enabled?() ->
        {:error, :disabled}

      order.source != "customer" ->
        {:error, :not_customer_order}

      order.status not in @prompt_statuses ->
        {:error, :invalid_status}

      true ->
        upsert_subscription(order, attrs)
    end
  end

  def notify_status_change(previous_status, %Order{} = order)
      when is_binary(previous_status) do
    if order.status != previous_status and notifiable?(order) do
      dispatch(order)
    end

    :ok
  end

  def notify_status_change(_previous_status, _order), do: :ok

  defp notifiable?(%Order{} = order) do
    enabled?() and
      order.source == "customer" and
      order.payment_status == "paid" and
      order.status in @notify_statuses
  end

  defp dispatch(%Order{} = order) do
    fun = fn -> deliver(order) end

    if async?() do
      Task.start(fun)
    else
      fun.()
    end
  end

  defp deliver(%Order{} = order) do
    payload = Jason.encode!(notification_payload(order))
    cutoff = cutoff_at()

    subscriptions =
      from(s in Subscription,
        where: s.order_id == ^order.id and s.inserted_at >= ^cutoff
      )
      |> Repo.all()

    Enum.each(subscriptions, fn subscription ->
      case adapter().send_web_push(payload, subscription_map(subscription), vapid_details()) do
        :ok ->
          :ok

        {:error, :gone} ->
          Repo.delete(subscription)

        {:error, reason} ->
          require Logger
          Logger.warning("customer push failed order=#{order.number} reason=#{inspect(reason)}")
      end
    end)
  end

  defp notification_payload(%Order{status: "preparing", number: number}) do
    %{
      title: "CoffeeSpot",
      body: "We're preparing #{number}.",
      url: order_path(number),
      tag: "order-#{number}"
    }
  end

  defp notification_payload(%Order{status: "ready", number: number}) do
    %{
      title: "CoffeeSpot",
      body: "Ready for pick up — #{number}. Show this at the counter.",
      url: order_path(number),
      tag: "order-#{number}"
    }
  end

  defp order_path(number), do: "/order/#{number}"

  defp upsert_subscription(order, attrs) do
    params = %{
      order_id: order.id,
      endpoint: Map.get(attrs, "endpoint") || Map.get(attrs, :endpoint),
      p256dh: nested_key(attrs, "p256dh") || nested_key(attrs, :p256dh),
      auth: nested_key(attrs, "auth") || nested_key(attrs, :auth)
    }

    %Subscription{}
    |> Subscription.changeset(params)
    |> Repo.insert(
      on_conflict: {:replace, [:p256dh, :auth, :updated_at]},
      conflict_target: [:order_id, :endpoint]
    )
  end

  defp nested_key(attrs, key) when is_map_key(attrs, key), do: Map.get(attrs, key)

  defp nested_key(attrs, key) do
    keys = Map.get(attrs, "keys") || Map.get(attrs, :keys) || %{}
    Map.get(keys, to_string(key)) || Map.get(keys, key)
  end

  defp subscription_map(%Subscription{} = subscription) do
    %{
      "endpoint" => subscription.endpoint,
      "keys" => %{
        "p256dh" => subscription.p256dh,
        "auth" => subscription.auth
      }
    }
  end

  defp vapid_details do
    %{
      subject: vapid_config()[:subject] || Endpoint.url(),
      public_key: vapid_config()[:public_key],
      private_key: vapid_config()[:private_key]
    }
  end

  defp vapid_config, do: Application.get_env(:espreso, __MODULE__, [])

  defp adapter do
    Keyword.get(vapid_config(), :adapter, Espreso.CustomerPush.WebPush)
  end

  defp async? do
    Keyword.get(vapid_config(), :async, true)
  end

  defp cutoff_at do
    DateTime.utc_now()
    |> DateTime.add(-@ttl_hours * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp vapid_private_key do
    case vapid_config()[:private_key] do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> :error
    end
  end
end
