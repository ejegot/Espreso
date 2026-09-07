defmodule EspresoWeb.HomeLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    :ok
  end

  test "GET / loads CoffeeSpot single page with signature hero", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "CoffeeSpot"
    assert has_element?(view, ".menu-page-brune")
    assert has_element?(view, ".brune-hero-signature")
    assert has_element?(view, ".brune-visit")
    assert has_element?(view, ".brune-vibes")
    assert has_element?(view, ".brune-socials")
    assert has_element?(view, ".brune-mega-footer")
    assert has_element?(view, ".site-instagram")
    refute has_element?(view, ".home-page-shade")
  end

  test "homepage has Brune header", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".brune-top-brand", "CoffeeSpot")
    assert has_element?(view, ".brune-top-nav")
  end

  test "homepage shows hero with Pure Tableya signature and tagline", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "bold coffee meets good vibes"

    assert has_element?(
             view,
             ".brune-hero-signature img[src='/images/coffeespot/signature-pure-tableya-portrait.jpg']"
           )
  end

  test "homepage shows social icons for FB, TikTok, Instagram", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".brune-social-card[aria-label='Facebook']")
    assert has_element?(view, ".brune-social-card[aria-label='TikTok']")
    assert has_element?(view, ".brune-social-card[aria-label='Instagram']")
  end

  test "homepage mega footer has hours, contact, location", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ".brune-mega-brand")
    assert has_element?(view, ".brune-mega-label", "Hours")
    assert has_element?(view, ".brune-mega-label", "Contact")
    assert has_element?(view, ".brune-mega-label", "Location")
  end

  test "/menu opens QR landing with Pure Tableya signature", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/menu")

    assert has_element?(view, "#menu-landing.menu-qr-landing--signature")
    assert has_element?(
             view,
             ~s(.menu-qr-landing-photo--signature[src="/images/coffeespot/signature-pure-tableya-portrait.jpg"])
           )
  end
end

