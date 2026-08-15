defmodule EspresoWeb.PageControllerTest do
  use EspresoWeb.ConnCase

  test "GET / serves the CoffeeSpot homepage", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "CoffeeSpot"
    assert html_response(conn, 200) =~ "Lilac"
  end
end
