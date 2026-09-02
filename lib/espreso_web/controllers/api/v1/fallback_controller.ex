defmodule EspresoWeb.Api.V1.FallbackController do
  use EspresoWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_credentials"})
  end

  def call(conn, {:error, :invalid_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_token"})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "forbidden"})
  end

  def call(conn, {:error, :invalid_status}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_status"})
  end

  def call(conn, {:error, :cancelled}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "cancelled"})
  end

  def call(conn, {:error, :online_payment_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "online_payment_required"})
  end

  def call(conn, {:error, :payment_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "payment_required"})
  end

  def call(conn, {:error, :empty_cart}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "empty_cart"})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", details: translate_errors(changeset)})
  end

  def call(conn, {:error, {:unavailable, names}}) when is_list(names) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "unavailable", products: names})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "unprocessable"})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
