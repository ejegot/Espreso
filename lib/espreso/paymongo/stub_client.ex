defmodule Espreso.PayMongo.StubClient do
  @moduledoc false

  @behaviour Espreso.PayMongo.Client

  @impl true
  def create_checkout_session(_order, _lines, opts) do
    session_id = "cs_test_" <> Integer.to_string(System.unique_integer([:positive]))

    checkout_url =
      Keyword.get(opts, :checkout_url, "https://checkout.paymongo.test/#{session_id}")

    {:ok, %{id: session_id, checkout_url: checkout_url}}
  end
end
