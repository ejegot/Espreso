defmodule EspresoWeb.ProductLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Marketing.ShopRequest
  alias Espreso.Repo

  test "GET /product is Espreso, not CoffeeSpot guest chrome", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/product")

    assert has_element?(
             view,
             "img.espreso-product-logo[src='/images/elilai-kafe/elilai-kafe-mark-product.png']"
           )
    assert has_element?(view, ".espreso-product-wordmark", "Elilai Kafe")
    assert has_element?(view, ".espreso-product-kicker-sub", "Café management system")
    assert html =~ "Run the café as one shift"
    assert html =~ "POS, kitchen, and QR menu"
    refute html =~ "CoffeeSpot"
    refute has_element?(view, ".espreso-product-kicker", "Espreso")
    assert html =~ "Request a café setup"
    refute has_element?(view, ".brune-hero")
    refute has_element?(view, ".menu-page-brune")
    assert has_element?(view, "#product-tab-signin[href='/login']", "Sign In")
    assert has_element?(view, "#product-tab-request", "Request access")
    assert has_element?(view, "#product-request-form")
  end

  test "submitting a valid request shows thanks and stores the row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/product")

    view
    |> form("#product-request-form",
      shop_request: %{
        contact_name: "Ana Cruz",
        cafe_name: "Lilac Brew",
        city: "Marikina",
        email: "ana@cafe.ph",
        mobile: "09171234567",
        note: "Two counters"
      }
    )
    |> render_submit()

    assert has_element?(view, "#product-request-thanks")
    refute has_element?(view, "#product-request-form")

    request = Repo.one!(ShopRequest)
    assert request.cafe_name == "Lilac Brew"
    assert request.phone_e164 == "+639171234567"
  end

  test "invalid request keeps the form and shows errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/product")

    html =
      view
      |> form("#product-request-form",
        shop_request: %{
          contact_name: "A",
          cafe_name: "Lilac Brew",
          city: "Marikina",
          email: "not-an-email",
          mobile: "123"
        }
      )
      |> render_submit()

    assert html =~ "must be a valid email"
    assert html =~ "must be a Philippine mobile"
    assert has_element?(view, "#product-request-form")
    refute has_element?(view, "#product-request-thanks")
    assert Repo.aggregate(ShopRequest, :count) == 0
  end

  test "honeypot submissions look successful but are not stored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/product")

    view
    |> form("#product-request-form",
      shop_request: %{
        contact_name: "Bot",
        cafe_name: "Spam Cafe",
        city: "Nowhere",
        email: "bot@spam.test",
        mobile: "09170000000",
        company_url: "https://spam.test"
      }
    )
    |> render_submit()

    assert has_element?(view, "#product-request-thanks")
    assert Repo.aggregate(ShopRequest, :count) == 0
  end
end
