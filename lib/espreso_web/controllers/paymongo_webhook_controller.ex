defmodule EspresoWeb.PayMongoWebhookController do
  use EspresoWeb, :controller

  alias Espreso.PayMongo

  def create(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("paymongo-signature") |> List.first()

    case PayMongo.verify_webhook_signature(raw_body, signature) do
      :ok ->
        with {:ok, payload} <- Jason.decode(raw_body),
             :ok <- PayMongo.verify_webhook_livemode(payload),
             :ok <- PayMongo.handle_webhook_event(payload) do
          json(conn, %{received: true})
        else
          {:error, :missing_livemode} ->
            conn |> put_status(:bad_request) |> json(%{error: "missing livemode"})

          {:error, :livemode_mismatch} ->
            conn |> put_status(:forbidden) |> json(%{error: "livemode mismatch"})

          {:error, :unconfigured_livemode} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: "paymongo mode not configured"})

          {:error, :amount_mismatch} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "amount mismatch"})

          {:error, :missing_amount} ->
            conn |> put_status(:bad_request) |> json(%{error: "missing amount"})

          {:error, :invalid_amount} ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid amount"})

          {:error, :invalid_order_total} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid order total"})

          {:error, :session_mismatch} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "session mismatch"})

          {:error, :missing_session} ->
            conn |> put_status(:bad_request) |> json(%{error: "missing session"})

          {:error, :order_cancelled} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "order cancelled"})

          {:error, _} ->
            json(conn, %{received: true})
        end

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})
    end
  end
end
