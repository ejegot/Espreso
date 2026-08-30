defmodule EspresoWeb.PayMongoWebhookController do
  use EspresoWeb, :controller

  alias Espreso.PayMongo

  def create(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("paymongo-signature") |> List.first()

    with :ok <- PayMongo.verify_webhook_signature(raw_body, signature),
         {:ok, payload} <- Jason.decode(raw_body) do
      _ = PayMongo.handle_webhook_event(payload)
      json(conn, %{received: true})
    else
      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})

      {:error, _} ->
        json(conn, %{received: true})
    end
  end
end
