# Production deployment (manual Docker)

This deploys the **Corobook app stack** (web + postgres + worker) on the server. It runs WITHOUT
its own reverse proxy: a **shared Caddy edge** — maintained separately as infra, since it fronts
several unrelated sites on the box — owns ports 80/443, terminates TLS, and routes to this app over
an external `edge` Docker network. This repo only knows how to run the app and join that network.

> The shared Caddy edge (its Caddyfile, compose, and the routing block for `corobook`) is **not**
> in this repo. Start it first; it creates the external `edge` network. This stack then joins it.

This is **manual**: you check out the repo on the server and run Docker Compose yourself.

## Quick start

On the server, from the repo root:

```sh
make -C deploy setup
```

That runs an interactive script which asks for the hostname, Rails master key, DB password and
mail settings, writes `deploy/.env.prod`, and brings up the Corobook stack (it checks the external
`edge` network exists first). Other targets: `make -C deploy help`.

## Prerequisites (on the server)

- Docker + the Docker Compose plugin.
- The repo checked out; your `config/master.key` value (for `RAILS_MASTER_KEY`).
- **The shared Caddy edge already running**, so the external `edge` network exists:
  `docker network inspect edge` should succeed. Its routing must include a block sending
  Corobook's hostname to `corobook-web:80` over the `edge` network, and Corobook's DNS must point
  at the server (the edge needs 80/443 open to issue the TLS cert).

## 1. Configure Corobook

```sh
cd deploy
cp .env.prod.example .env.prod
```

Set in `deploy/.env.prod`:

- `APP_HOST` — Corobook's hostname (for links in emails + the church-subdomain base).
- `RAILS_MASTER_KEY` — contents of `config/master.key`.
- `COROBOOK_NEXT_DATABASE_PASSWORD` — a strong password (Postgres role + app).
- `MAIL_DOMAIN` / `MAIL_FROM` — optional (see `docs/mail-setup.md`).

## 2. Bring up Corobook

```sh
# from deploy/
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
# or: make up
```

Services: `postgres`, `web` (container `corobook-web`, first boot runs `db:prepare` to create the
4 prod DBs: primary/cache/queue/cable), `worker` (Solid Queue). No published ports — the shared edge
reaches `corobook-web:80` over the `edge` network. Verify through the edge:

```sh
curl -I https://<APP_HOST>/up   # expect HTTP/2 200
```

## Updating / teardown

```sh
# update Corobook
git pull && cd deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build   # or: make rebuild

# stop Corobook (keep data) / wipe data (destructive)
docker compose --env-file .env.prod -f docker-compose.prod.yml down            # or: make down
docker compose --env-file .env.prod -f docker-compose.prod.yml down -v         # or: make destroy
```

The shared edge is independent — redeploying this app does not touch it.

## Notes

- **SSL**: TLS terminates at the shared Caddy edge; the app runs with `assume_ssl`/`force_ssl`, so
  it trusts the forwarded proto and won't redirect-loop.
- **DuckDNS + subdomain login**: church subdomains resolve by stripping the configured `APP_HOST`
  base, so `gracia.<APP_HOST>` works and the bare host shows the picker. (Each church subdomain you
  actually use needs its own DNS record + an edge routing block, or a wildcard cert.)
- This is a **single-box** deploy: no backups/offsite yet. Add those before relying on it.
