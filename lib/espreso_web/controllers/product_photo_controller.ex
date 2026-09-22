defmodule EspresoWeb.ProductPhotoController do
  use EspresoWeb, :controller

  alias Espreso.Menu

  def show(conn, %{"id" => id}) do
    with {product_id, ""} <- Integer.parse(id),
         %Espreso.Menu.ProductPhoto{} = photo <- Menu.get_product_photo(product_id) do
      conn
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> put_resp_content_type(photo.content_type)
      |> send_resp(200, photo.data)
    else
      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
