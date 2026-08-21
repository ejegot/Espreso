defmodule Espreso.CoffeeSpot do
  @moduledoc """
  Public CoffeeSpot – Lilac Marikina contact, place, and about details.
  """

  alias Espreso.Menu

  def location, do: "Lilac, Marikina"

  def address, do: "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811"

  def address_display,
    do: "CoffeeSpot – Lilac, Marikina, 84 Lilac St. Concepcion Dos, Marikina City, Philippines, 1811"

  def place_line, do: "CoffeeSpot · Lilac, Marikina"

  def tagline, do: "The place where bold coffee meets good vibes."

  def vibes_eyebrow, do: "The vibes"

  def vibes_quote,
    do:
      "Unmatched vibes, great coffee, and a vibrant space that's all about community and creativity."

  def address_short, do: "84 Lilac St., Concepcion Dos, Marikina City, Philippines"

  @doc """
  Short lines for the Brune-style visit strip and footer hours column.
  """
  def hours_lines do
    [
      "Mon–Thu · 8:00 AM – 12:00 AM",
      "Fri–Sun · 8:00 AM – 10:00 PM",
      "Student Hour · Mon–Thu, 2:00 PM – 5:00 PM",
      "Holiday hours on Instagram"
    ]
  end

  @doc """
  Featured promo cards for the Home page "What's brewing" section.
  """
  def promo_cards do
    [
      %{
        id: :midnight_haven,
        badge: "Coming September",
        title: "Your New Midnight Haven",
        body:
          "We're extending our hours for students and night owls. Fast Wi-Fi, premium coffee, and cozy industrial vibes — open late for study sessions and deadlines.",
        image: "/images/coffeespot/promo-midnight-haven.jpg",
        image_alt: "CoffeeSpot interior at night with laptop and coffee"
      },
      %{
        id: :student_discount,
        badge: "Starting Sept 4",
        title: "Student Discount Hour",
        body:
          "Marikina students, this one's for you. Drop by Mon–Thu from 2:00 PM to 5:00 PM, flash your valid School ID, and get a free size upgrade on iced drinks.",
        image: "/images/coffeespot/promo-student-discount.jpg",
        image_alt: "Large iced Spanish Latte at CoffeeSpot"
      }
    ]
  end

  @doc """
  Slim promo note shown on the Menu page above item listings.
  """
  def student_promo_note do
    "Students: Free size upgrade on iced drinks — Mon–Thu, 2:00 PM – 5:00 PM. Show valid School ID at counter."
  end

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
      "Extended hours",
      "Fast Wi-Fi",
      "Study-friendly space",
      "In-store pickup",
      "Dine-in",
      "Takeout",
      "Outdoor seating"
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

  @doc """
  Digits-only phone for WhatsApp (`wa.me`), e.g. `639566728906`.
  """
  def whatsapp_digits, do: phone_tel() |> String.replace(~r/\D/, "")

  @doc """
  Prefills a WhatsApp chat to CoffeeSpot with the customer's basket.

  Each line is a map with `:name`, `:size` (optional), `:quantity`, and `:price` (Decimal).

  Optional `checkout` map keys:
  - `:customer_name` (string)
  - `:fulfillment` (`:dine_in` or `:pickup`)
  - `:table_number` (string, for dine-in)
  - `:notes` (string, optional)
  """
  def order_whatsapp_url(lines, checkout \\ %{}) when is_list(lines) and lines != [] do
    "https://wa.me/#{whatsapp_digits()}?text=#{URI.encode_www_form(order_message(lines, checkout))}"
  end

  @doc """
  Human-readable order message for WhatsApp handoff.
  """
  def order_message(lines, checkout \\ %{}) when is_list(lines) and lines != [] do
    items =
      lines
      |> Enum.map_join("\n", &format_order_line/1)

    total =
      lines
      |> Enum.reduce(Decimal.new(0), fn line, acc ->
        Decimal.add(acc, Decimal.mult(line.price, line.quantity))
      end)
      |> Menu.format_price()

    name = checkout |> Map.get(:customer_name, "") |> to_string() |> String.trim()
    notes = checkout |> Map.get(:notes, "") |> to_string() |> String.trim()
    fulfillment = Map.get(checkout, :fulfillment, :pickup)

    type_line =
      case fulfillment do
        :dine_in ->
          table = checkout |> Map.get(:table_number, "") |> to_string() |> String.trim()
          "Type: Dine-in · Table #{table}"

        _ ->
          "Type: Pickup at counter"
      end

    name_line = if name != "", do: "Name: #{name}\n", else: ""
    notes_block = if notes != "", do: "\n\nNotes: #{notes}", else: ""

    """
    Hi CoffeeSpot! New order

    #{name_line}#{type_line}

    #{items}

    Total: #{total}#{notes_block}
    """
    |> String.trim()
  end

  defp format_order_line(%{name: name, quantity: qty, price: price} = line) do
    size = Map.get(line, :size)
    size_part = if is_binary(size) and size != "", do: " (#{size})", else: ""
    line_total = Decimal.mult(price, qty)
    "• #{qty}x #{name}#{size_part} — #{Menu.format_price(line_total)}"
  end

  def email, do: "elilaicorp.ph@gmail.com"

  def email_url, do: "mailto:elilaicorp.ph@gmail.com"

  def instagram_handle, do: "coffeespot_lilac.marikina"

  def instagram_url, do: "https://www.instagram.com/coffeespot_lilac.marikina/"

  def facebook_label, do: "Coffee Spot-Lilac, Marikina"

  def facebook_url, do: "https://www.facebook.com/profile.php?id=61572602608495"

  def tiktok_handle, do: "coffeespotlilac_"

  def tiktok_url, do: "https://www.tiktok.com/@coffeespotlilac_"

  @doc """
  Public social profiles for header icon links.
  """
  def social_links do
    [
      %{id: :instagram, href: instagram_url(), label: "Instagram"},
      %{id: :facebook, href: facebook_url(), label: "Facebook"},
      %{id: :tiktok, href: tiktok_url(), label: "TikTok"}
    ]
  end

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
