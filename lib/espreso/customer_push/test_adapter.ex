defmodule Espreso.CustomerPush.TestAdapter do
  @moduledoc false

  def send_web_push(message, subscription, _vapid) when is_binary(message) do
    payload =
      case Jason.decode(message) do
        {:ok, decoded} -> decoded
        _ -> message
      end

    send(self(), {Espreso.CustomerPush, payload, subscription})
    :ok
  end
end
