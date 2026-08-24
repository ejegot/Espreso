defmodule Espreso.Repo.Migrations.CreateBusinessSettings do
  use Ecto.Migration

  def change do
    create table(:business_settings) do
      add :business_name, :string, null: false
      add :address, :string, null: false
      add :phone, :string, null: false
      add :email, :string, null: false
      add :hours_lines, {:array, :string}, null: false, default: []
      add :instagram_url, :string, null: false
      add :facebook_url, :string, null: false
      add :tiktok_url, :string, null: false
      # Forces at most one settings row.
      add :singleton_key, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create unique_index(:business_settings, [:singleton_key])

    execute(
      """
      INSERT INTO business_settings (
        business_name,
        address,
        phone,
        email,
        hours_lines,
        instagram_url,
        facebook_url,
        tiktok_url,
        singleton_key,
        inserted_at,
        updated_at
      ) VALUES (
        'CoffeeSpot',
        '84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811',
        '+639566728906',
        'elilaicorp.ph@gmail.com',
        ARRAY[
          'Mon–Thu · 8:00 AM – 12:00 AM',
          'Fri–Sun · 8:00 AM – 10:00 PM',
          'Student Hour · Mon–Thu, 2:00 PM – 5:00 PM',
          'Holiday hours on Instagram'
        ],
        'https://www.instagram.com/coffeespot_lilac.marikina/',
        'https://www.facebook.com/profile.php?id=61572602608495',
        'https://www.tiktok.com/@coffeespotlilac_',
        1,
        NOW() AT TIME ZONE 'utc',
        NOW() AT TIME ZONE 'utc'
      )
      """,
      "DELETE FROM business_settings"
    )
  end
end
