defmodule EspresoWeb.ErrorJSONTest do
  use EspresoWeb.ConnCase, async: true

  test "renders 404" do
    assert EspresoWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert EspresoWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
