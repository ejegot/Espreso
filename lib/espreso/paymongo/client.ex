defmodule Espreso.PayMongo.Client do
  @moduledoc false

  @type checkout_result :: %{id: String.t(), checkout_url: String.t()}

  @callback create_checkout_session(
              order :: Espreso.Orders.Order.t(),
              lines :: [map()],
              opts :: keyword()
            ) :: {:ok, checkout_result()} | {:error, term()}
end
