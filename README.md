# Espreso

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Shop sessions

Staff record opening cash to start a shop session and explicitly close it after
counting the drawer. The business date is the Manila date of opening; sales and
cash movements after midnight remain in that session. Staff attendance is
separate, and opening hours do not automatically close the shop.

**Cutover:** apply the session migration only while the shop is closed. Existing
unmatched opening records remain historical and incomplete; they are not made
active and no close timestamp is invented. Record a fresh opening at the next
operation. Once multiple sessions have been recorded for one business date,
rolling back the migration requires resolving those rows first.

## Deploy to DigitalOcean

After merging changes into `main`, run this from a clean Espreso checkout:

```sh
bash scripts/deploy_digitalocean.sh
```

The script fast-forwards local `main` to `origin/main`, builds that exact
commit's Docker image on the Droplet, preserves the current container
environment, and checks `/login` before finishing. It requires a clean
checkout and refuses to deploy unpublished commits. It does not run database
migrations or seed/import data. The prior container is kept stopped for
rollback. To override the defaults, set `DO_HOST`, `DO_SSH_USER`,
`DO_REMOTE_BASE`, or `DO_HEALTH_URL`.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
