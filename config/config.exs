# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :espreso,
  ecto_repos: [Espreso.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Absolute URL encoded in CoffeeSpot QR codes (destination: `/menu`).
  # Override at runtime with PUBLIC_MENU_URL (e.g. https://your-domain.com/menu).
  public_menu_url: "http://localhost:4000/menu",
  # Staff board at /orders — override with STAFF_ORDERS_PASSWORD in production.
  staff_orders_password: "coffeespot"

# Configures the endpoint
config :espreso, EspresoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EspresoWeb.ErrorHTML, json: EspresoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Espreso.PubSub,
  live_view: [signing_salt: "9+95ruWr"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :espreso, Espreso.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  espreso: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  espreso: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :espreso, :paymongo,
  client: Espreso.PayMongo.HTTPClient,
  secret_key: nil,
  webhook_secret: nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
