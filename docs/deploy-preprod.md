# Preprod deployment (manual Docker + a shared Caddy edge)

This box hosts several sites — Corobook, your other Docker app, and a static HTML page. One
**shared Caddy** owns ports 80/443 and fronts all of them with automatic HTTPS (Let's Encrypt).
Each app stack runs WITHOUT its own proxy and joins a shared `edge` Docker network that Caddy
routes over.

This is **manual**: you check out the repo on the server and run Docker Compose yourself.

```
            ┌───────────── Caddy (deploy/edge) — owns :80/:443, auto-HTTPS ─────────────┐
 Internet ─►│  corobook-preprod.duckdns.org → corobook-web:80  (Corobook, this repo)     │
            │  <your-app-host>              → <your-app>:<port> (your other Docker app)   │
            │  <static-host>                → file_server /srv/static (your static site)  │
            └────────────────────────────────── edge network ───────────────────────────┘
```

## Prerequisites (on the server)

- Docker + the Docker Compose plugin; ports **80 and 443** open to the internet.
- The repo checked out; your `config/master.key` value (for `RAILS_MASTER_KEY`).
- Each site's hostname (DuckDNS or otherwise) pointing at this server's public IP.

## 1. Point DNS at the server

For each hostname (start with Corobook's, e.g. `corobook-preprod.duckdns.org`), set its A record to
the server's public IP. Confirm: `dig +short corobook-preprod.duckdns.org` → your IP. TLS won't
issue until this resolves and 80/443 are reachable.

## 2. Bring up the shared edge (once)

```sh
cd deploy/edge
cp .env.edge.example .env.edge        # set COROBOOK_HOST
docker compose --env-file .env.edge up -d
```

This starts Caddy and creates the shared **`edge`** network. By default it routes only Corobook;
add your other app and the static site in step 5.

## 3. Configure Corobook

```sh
cd ../                                 # deploy/
cp .env.preprod.example .env.preprod
```

Set in `deploy/.env.preprod`:

- `APP_HOST` — Corobook's hostname (same as `COROBOOK_HOST`), for links in emails + subdomain base.
- `RAILS_MASTER_KEY` — contents of `config/master.key`.
- `COROBOOK_NEXT_DATABASE_PASSWORD` — a strong password (Postgres role + app).
- `MAIL_DOMAIN` / `MAIL_FROM` — optional on preprod (see `docs/mail-setup.md`).

## 4. Bring up Corobook

```sh
# from deploy/
docker compose --env-file .env.preprod -f docker-compose.preprod.yml up -d --build
```

Services: `postgres`, `web` (container `corobook-web`, first boot runs `db:prepare`), `worker`
(Solid Queue). No published ports — the edge Caddy reaches `corobook-web:80` over the `edge`
network. Verify:

```sh
curl -I https://corobook-preprod.duckdns.org/up   # expect HTTP/2 200
```

## 5. Add your other two sites to the same Caddy

Edit `deploy/edge/Caddyfile` (both example blocks are commented out):

- **Other Docker app** — attach its container to the `edge` network. In its own compose add:
  ```yaml
  networks: [ default, edge ]
  # ...
  networks:
    edge:
      external: true
      name: edge
  ```
  Then uncomment the app block in the Caddyfile and set its hostname + `reverse_proxy
  <container-name>:<port>`.
- **Static HTML site** — copy its files into `deploy/edge/static/`, uncomment the static block,
  set its hostname.

Reload Caddy after editing:

```sh
cd deploy/edge
docker compose --env-file .env.edge up -d   # picks up the Caddyfile change
# or: docker compose --env-file .env.edge exec caddy caddy reload --config /etc/caddy/Caddyfile
```

Caddy fetches a cert for each new hostname automatically.

## Updating / teardown

```sh
# update Corobook
git pull && cd deploy
docker compose --env-file .env.preprod -f docker-compose.preprod.yml up -d --build

# stop Corobook (keep data) / wipe data (destructive)
docker compose --env-file .env.preprod -f docker-compose.preprod.yml down
docker compose --env-file .env.preprod -f docker-compose.preprod.yml down -v
```

The edge Caddy stays up across app redeploys. Bring order down as: app stacks first, edge last (so
nothing references the `edge` network when you remove it).

## Notes

- **Certs** live in the `caddy_data` volume — restarts don't re-request them (Let's Encrypt
  rate-limit safe). Don't `down -v` the edge casually.
- **SSL**: TLS terminates at Caddy; the app runs with `assume_ssl`/`force_ssl`, so it trusts the
  forwarded proto and won't redirect-loop.
- **DuckDNS + subdomain login**: church subdomains resolve by stripping the configured `APP_HOST`
  base, so `gracia.corobook-preprod.duckdns.org` works and the bare host shows the picker. (Each
  church subdomain you actually use needs its own DNS record + a Caddy block or a wildcard.)
- This is **preprod**: single box, no backups/offsite. Harden before production.
