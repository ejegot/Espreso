defmodule EspresoWeb.Api.V1.MenuController do
  use EspresoWeb, :controller

  alias Espreso.Menu
  alias EspresoWeb.Api.JSON

  def index(conn, _params) do
    json(conn, %{menu: JSON.menu(Menu.list_menu())})
  end
end
