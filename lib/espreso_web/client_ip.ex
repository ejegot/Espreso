defmodule EspresoWeb.ClientIP do
  @moduledoc """
  Best-effort client IP for auth throttling.

  Uses `Plug.Conn.remote_ip` (peer address) only. There is no established
  trusted-forwarded-IP helper in this app; arbitrary `X-Forwarded-For` values
  are not trusted.
  """

  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(%Plug.Conn{remote_ip: ip}) when is_tuple(ip) do
    ip |> :inet.ntoa() |> to_string()
  end

  def from_conn(_), do: "unknown"
end
