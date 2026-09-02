defmodule EspresoWeb.Api.V1.SettingsController do
  use EspresoWeb, :controller

  alias EspresoWeb.Api.JSON

  def business(conn, _params) do
    json(conn, %{settings: JSON.business_settings()})
  end
end
