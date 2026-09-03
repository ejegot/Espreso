# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Espreso.Repo.insert!(%Espreso.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias Espreso.BusinessSettings
alias Espreso.Repo
alias Espreso.Menu.{Category, Product, ProductPrice}

# —— Business settings (singleton) ——
settings = BusinessSettings.ensure_defaults!()
IO.puts("Business settings ready: #{settings.business_name}")

gcash_qr_path = "/images/coffeespot/gcash-qrph.png"

settings =
  settings
  |> Ecto.Changeset.change(%{
    payments_mode: "qrph_manual",
    gcash_qrph_path: gcash_qr_path,
    maya_qrph_path: nil
  })
  |> Repo.update!()

IO.puts("Payments mode: #{settings.payments_mode}, GCash QR: #{settings.gcash_qrph_path}")

find_or_create_category = fn name ->
  case Repo.get_by(Category, name: name) do
    nil ->
      %Category{}
      |> Category.changeset(%{name: name})
      |> Repo.insert!()

    category ->
      category
  end
end

seed_products = fn category, products ->
  Enum.each(products, fn {product_name, prices} ->
    product =
      case Repo.get_by(Product, name: product_name, category_id: category.id) do
        nil ->
          %Product{}
          |> Product.changeset(%{
            name: product_name,
            category_id: category.id,
            available: true
          })
          |> Repo.insert!()

        existing_product ->
          existing_product
          |> Product.changeset(%{available: true})
          |> Repo.update!()
      end

    Enum.each(prices, fn {size, price} ->
      existing_price =
        ProductPrice
        |> where([pp], pp.product_id == ^product.id)
        |> then(fn query ->
          if is_nil(size) do
            where(query, [pp], is_nil(pp.size))
          else
            where(query, [pp], pp.size == ^size)
          end
        end)
        |> Repo.one()

      if is_nil(existing_price) do
        %ProductPrice{}
        |> ProductPrice.changeset(%{
          product_id: product.id,
          size: size,
          price: Decimal.new(price)
        })
        |> Repo.insert!()
      else
        existing_price
        |> ProductPrice.changeset(%{price: Decimal.new(price)})
        |> Repo.update!()
      end
    end)
  end)
end

retire_food_products = fn names ->
  food_category = find_or_create_category.("FOOD")

  Product
  |> where([p], p.category_id == ^food_category.id and p.name in ^names)
  |> Repo.update_all(set: [available: false])
end

rename_product = fn category_name, old_name, new_name ->
  category = find_or_create_category.(category_name)

  case Repo.get_by(Product, name: old_name, category_id: category.id) do
    nil ->
      :ok

    product ->
      product
      |> Product.changeset(%{name: new_name})
      |> Repo.update!()
  end
end

rename_product.("SODA", "Green Apple Campaign", "Green Apple Campagna")

hot_category = find_or_create_category.("HOT")

hot_products = [
  {"Espresso", [{nil, "75"}]},
  {"Double Espresso", [{nil, "85"}]},
  {"Americano", [{"8oz", "110"}, {"12oz", "120"}]},
  {"Café Latte", [{"8oz", "150"}, {"12oz", "160"}]},
  {"Cappuccino", [{"8oz", "160"}, {"12oz", "170"}]},
  {"Spanish Latte", [{"8oz", "160"}, {"12oz", "170"}]},
  {"Mocha Latte", [{"8oz", "160"}, {"12oz", "170"}]},
  {"Caramel Macchiato", [{"8oz", "160"}, {"12oz", "170"}]},
  {"Butter Scotch", [{"8oz", "160"}, {"12oz", "170"}]},
  {"Matcha Latte", [{"8oz", "160"}, {"12oz", "170"}]},
  {"Hot Belagio Chocolate", [{"8oz", "160"}, {"12oz", "170"}]}
]

seed_products.(hot_category, hot_products)

cold_category = find_or_create_category.("COLD")

cold_products = [
  {"Americano", [{"16oz", "140"}]},
  {"Café Latte", [{"16oz", "180"}]},
  {"Mocha Latte", [{"16oz", "180"}]},
  {"Hazelnut", [{"16oz", "180"}]},
  {"Macadamia", [{"16oz", "180"}]},
  {"Roasted Almond", [{"16oz", "180"}]},
  {"English Toffee", [{"16oz", "180"}]},
  {"Caramel Macchiato", [{"16oz", "180"}]},
  {"Spanish Latte", [{"16oz", "180"}]},
  {"Butter Scotch", [{"16oz", "180"}]},
  {"Matcha Caramel", [{"16oz", "180"}]},
  {"Strawberry Matcha", [{"16oz", "180"}]},
  {"Choco Berry", [{"16oz", "180"}]},
  {"Iced Bellagio Choco", [{"16oz", "180"}]}
]

seed_products.(cold_category, cold_products)

frappe_category = find_or_create_category.("FRAPPE")

frappe_products = [
  {"Salted Caramel", [{"16oz", "180"}]},
  {"Mocha", [{"16oz", "180"}]},
  {"Butter Scotch", [{"16oz", "180"}]},
  {"Mocha Crumble", [{"16oz", "180"}]},
  {"Biscoff", [{"16oz", "180"}]},
  {"Cookies & Cream", [{"16oz", "180"}]},
  {"Matcha", [{"16oz", "180"}]},
  {"Double Chocolate", [{"16oz", "180"}]},
  {"Vanilla Bean Hazelnut", [{"16oz", "180"}]},
  {"Strawberry", [{"16oz", "180"}]}
]

seed_products.(frappe_category, frappe_products)

soda_category = find_or_create_category.("SODA")

soda_products = [
  {"Tropical Passion Fruit", [{"16oz", "120"}]},
  {"Green Apple Campagna", [{"16oz", "120"}]},
  {"Minty Peach", [{"16oz", "120"}]},
  {"Scarlet Berry", [{"16oz", "120"}]},
  {"Majestic Mango", [{"16oz", "120"}]},
  {"Peach Berry", [{"16oz", "120"}]},
  {"Hummingbird", [{"16oz", "120"}]}
]

seed_products.(soda_category, soda_products)

food_category = find_or_create_category.("FOOD")

food_products = [
  # Rice Meal
  {"Chicken Flakes", [{nil, "179"}]},
  {"Beef Tapa", [{nil, "179"}]},
  {"Corned Beef", [{nil, "179"}]},
  {"Spam", [{nil, "179"}]},
  {"Pork Liempo", [{nil, "249"}]},
  {"Spam Musubi", [{nil, "75"}]},
  {"Nugget", [{nil, "179"}]},
  # Appetizers
  {"Solo Fries", [{nil, "99"}]},
  {"Fries w/ Nuggets", [{nil, "199"}]},
  {"Beef Nachos", [{nil, "249"}]},
  {"Quesadillas", [{nil, "249"}]},
  {"Chicken & Chips", [{nil, "150"}]},
  {"Spam & Chips", [{nil, "150"}]},
  # Sandwiches & Wraps
  {"Slow-Roasted Chicken Sourdough", [{nil, "249"}]},
  {"Golden Egg Royale", [{nil, "199"}]},
  {"Tuna Royale Baguette", [{nil, "249"}]},
  # Muffins
  {"Big Assorted Muffin", [{nil, "99"}]},
  # Cakes / Breads
  {"Dark Choco Dream Cake", [{nil, "229"}]},
  {"Choco Chip Cookies", [{nil, "65"}]},
  {"BNN Moist Slice", [{nil, "75"}]},
  {"Choco Moist Slice", [{nil, "75"}]},
  {"Carrot Moist Slice", [{nil, "75"}]},
  {"Belgian Waffles", [{nil, "149"}]},
  {"Chocolate Almond Waffles", [{nil, "149"}]}
]

seed_products.(food_category, food_products)

retire_food_products.([
  "BNN Cream Cheese",
  "BNN Choco Overload",
  "BNN Biscoff",
  "Choco Chips",
  "Red Velvet"
])

# —— Staff accounts (Phase A) ——
alias Espreso.Accounts

owner_email = System.get_env("OWNER_EMAIL") || "owner@coffeespot.local"
owner_password = System.get_env("OWNER_PASSWORD") || "coffeespot1"

case Accounts.ensure_owner!(%{
       name: "Owner",
       email: owner_email,
       password: owner_password,
       role: "owner"
     }) do
  {:ok, user} ->
    IO.puts("Owner ready: #{user.email}")

  {:error, changeset} ->
    IO.puts("Owner seed skipped/failed: #{inspect(changeset.errors)}")
end

# —— Local dashboard role-testing accounts (dev/test only) ——
# Idempotent: create if missing; never update existing users.
dashboard_seed_accounts = [
  %{
    name: "Dashboard Owner",
    email: "owner.dashboard@test.local",
    password: "Dashboard123!",
    role: "owner",
    active: true
  },
  %{
    name: "Dashboard Manager",
    email: "manager.dashboard@test.local",
    password: "Dashboard123!",
    role: "manager",
    active: true
  },
  %{
    name: "Dashboard Staff",
    email: "staff.dashboard@test.local",
    password: "Dashboard123!",
    role: "barista",
    active: true
  },
  %{
    name: "Ana Reyes",
    email: "ana.barista@coffeespot.local",
    password: "Dashboard123!",
    role: "barista",
    active: true
  },
  %{
    name: "Marco Santos",
    email: "marco.barista@coffeespot.local",
    password: "Dashboard123!",
    role: "barista",
    active: true
  },
  %{
    name: "Liza Cruz",
    email: "liza.manager@coffeespot.local",
    password: "Dashboard123!",
    role: "manager",
    active: true
  }
]

for attrs <- dashboard_seed_accounts do
  case Accounts.get_user_by_email(attrs.email) do
    %Accounts.User{} = user ->
      IO.puts("Dashboard seed account already exists: #{user.email} (#{user.role})")

    nil ->
      case Accounts.register_user(attrs) do
        {:ok, user} ->
          IO.puts("Dashboard seed account created: #{user.email} (#{user.role})")

        {:error, changeset} ->
          IO.puts(
            "Dashboard seed account failed for #{attrs.email}: #{inspect(changeset.errors)}"
          )
      end
  end
end

dashboard_pin_seed = [
  {"staff.dashboard@test.local", "4321"},
  {"manager.dashboard@test.local", "5678"},
  {"ana.barista@coffeespot.local", "1111"},
  {"marco.barista@coffeespot.local", "2222"},
  {"liza.manager@coffeespot.local", "3333"}
]

for {email, pin} <- dashboard_pin_seed do
  case Accounts.get_user_by_email(email) do
    %Accounts.User{} = user ->
      case Accounts.set_pin(user, pin) do
        {:ok, _} -> IO.puts("Dashboard seed PIN set: #{email}")
        {:error, reason} -> IO.puts("Dashboard seed PIN failed for #{email}: #{inspect(reason)}")
      end

    nil ->
      :ok
  end
end
