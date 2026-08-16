defmodule Espreso.CoffeeSpot do
  @moduledoc """
  Public CoffeeSpot – Lilac Marikina contact, place, and about details.
  """

  def location, do: "Lilac, Marikina"

  def address, do: "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811"

  def address_display,
    do: "CoffeeSpot – Lilac, Marikina, 84 Lilac St. Concepcion Dos, Marikina City, Philippines, 1811"

  def place_line, do: "CoffeeSpot · Lilac, Marikina"

  def service_area, do: "Marikina City, Philippines"

  def hours_label, do: "Open now"

  def hours_note, do: "Hours · check Instagram for holiday updates"

  def map_embed_url,
    do:
      "https://maps.google.com/maps?q=#{URI.encode_www_form("84 Lilac St Concepcion Dos Marikina City 1811")}&z=16&output=embed"

  def map_link_url,
    do:
      "https://www.google.com/maps/search/?api=1&query=#{URI.encode_www_form("84 Lilac St Concepcion Dos Marikina City")}"

  def intro,
    do:
      "A minimalist haven in Marikina's business district, CoffeeSpot has been serving premium Italian-sourced beans for over five years. Our thoughtfully curated space offers the perfect retreat for busy professionals and coffee enthusiasts alike."

  def district_blurb,
    do: "A minimalist haven in Marikina's business district."

  def specialties do
    [
      "Online booking",
      "In-store pickup",
      "Dine-in",
      "Takeout",
      "Outdoor seating",
      "Reservations"
    ]
  end

  def reviews do
    [
      %{
        name: "Phillip Aseron",
        rating: 5,
        recommend?: true,
        body:
          "If you're looking for one of the best coffee spots in Marikina, this place is definitely worth a visit."
      },
      %{
        name: "Phem Baylen",
        rating: 5,
        recommend?: false,
        body: "Great place and masarap ang coffee."
      }
    ]
  end

  def phone_display, do: "+639566728906"

  def phone_tel, do: "+639566728906"

  def email, do: "elilaicorp.ph@gmail.com"

  def email_url, do: "mailto:elilaicorp.ph@gmail.com"

  def instagram_handle, do: "coffeespot_lilac.marikina"

  def instagram_url, do: "https://www.instagram.com/coffeespot_lilac.marikina/"

  def facebook_label, do: "Coffee Spot-Lilac, Marikina"

  def facebook_url, do: "https://www.facebook.com/profile.php?id=61572602608495"

  def tiktok_handle, do: "coffeespotlilac_"

  def tiktok_url, do: "https://www.tiktok.com/@coffeespotlilac_"

  def contact_links do
    [
      %{
        id: :instagram,
        href: instagram_url(),
        label: "Instagram",
        detail: instagram_handle(),
        external?: true
      },
      %{
        id: :facebook,
        href: facebook_url(),
        label: "Facebook",
        detail: facebook_label(),
        external?: true
      },
      %{
        id: :tiktok,
        href: tiktok_url(),
        label: "TikTok",
        detail: tiktok_handle(),
        external?: true
      },
      %{
        id: :email,
        href: email_url(),
        label: "Email",
        detail: email(),
        external?: false
      },
      %{
        id: :phone,
        href: "tel:#{phone_tel()}",
        label: "Phone",
        detail: phone_display(),
        external?: false
      }
    ]
  end
end
