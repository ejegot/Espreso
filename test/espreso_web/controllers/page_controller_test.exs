defmodule EspresoWeb.PageControllerTest do
  use EspresoWeb.ConnCase

  test "GET / redirects into the CoffeeSpot LiveView home", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "CoffeeSpot"
    assert html_response(conn, 200) =~ "Lilac Marikina"
  end
end
