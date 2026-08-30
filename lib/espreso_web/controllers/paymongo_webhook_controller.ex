defmodule EspresoWeb.PayMongoWebhookController do
  use EspresoWeb, :controller

  alias Espreso.PayMongo

  def create(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("paymongo-signature") |> List.first()

    case PayMongo.verify_webhook_signature(raw_body, signature) do
      :ok ->
        with {:ok, payload} <- Jason.decode(raw_body),
             :ok <- PayMongo.verify_webhook_livemode(payload) do
          _ = PayMongo.handle_webhook_event(payload)
          json(conn, %{received: true})
        else
          {:error, :missing_livemode} ->
            conn |> put_status(:bad_request) |> json(%{error: "missing livemode"})

          {:error, :livemode_mismatch} ->
            conn |> put_status(:forbidden) |> json(%{error: "livemode mismatch"})

          {:error, :unconfigured_livemode} ->
            conn |> put_status(:service_unavailable) |> json(%{error: "paymongo mode not configured"})

          {:error, _} ->
            json(conn, %{received: true})
        end

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})
    end
  end
end
