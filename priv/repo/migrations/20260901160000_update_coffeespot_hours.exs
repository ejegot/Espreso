defmodule Espreso.Repo.Migrations.UpdateCoffeespotHours do
  use Ecto.Migration

  @hours_lines [
    "Sun–Wed · 11:00 AM – 11:00 PM",
    "Thu · 11:00 AM – 12:00 AM",
    "Fri–Sat · 11:00 AM – 2:00 AM",
    "Holiday hours on Instagram"
  ]

  def up do
    repo().update_all(
      "business_settings",
      [set: [hours_lines: @hours_lines, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]],
      []
    )
  end

  def down do
    repo().update_all(
      "business_settings",
      [
        set: [
          hours_lines: [
            "Mon–Thu · 8:00 AM – 12:00 AM",
            "Fri–Sun · 8:00 AM – 10:00 PM",
            "Student Hour · Mon–Thu, 2:00 PM – 5:00 PM",
            "Holiday hours on Instagram"
          ],
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      ],
      []
    )
  end
end
