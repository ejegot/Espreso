defmodule EspresoWeb.Plugs.RawBodyReader do
  @moduledoc false

  @doc """
  Caches the raw request body on the connection for webhook signature checks.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn =
          conn
          |> Plug.Conn.assign(:raw_body, append_body(conn.assigns[:raw_body], body))
          |> Plug.Conn.assign(:raw_body_chunk, body)

        {:ok, body, conn}

      more ->
        more
    end
  end

  defp append_body(nil, body), do: body
  defp append_body(existing, body), do: existing <> body
end
