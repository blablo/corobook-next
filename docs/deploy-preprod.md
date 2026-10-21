# Preprod deployment (manual, Docker + Caddy + DuckDNS)

Deploy Corobook to a preprod server you control by checking out the repo and running Docker
Compose on the box. TLS is automatic (Caddy + Let's Encrypt) on a DuckDNS hostname.

This is **manual**: there's no SSH automation or registry push — you run the commands on the server.

---

## Prerequisites (on the preprod server)

- Docker + the Docker Compose plugin.
- Ports **80 and 443** open to the internet (Let's Encrypt validates over 80; traffic serves on 443).
- Git, and the repo checked out.
- Your `config/master.key` value (for `RAILS_MASTER_KEY`) — never commit it.

## 1. Point DuckDNS at the server

1. In your [DuckDNS](https://www.duckdns.org) account, pick/confirm a subdomain, e.g.
   `corobook-preprod`.
2. Set its IP to the server's **public IP** (the DuckDNS dashboard, or the standard
   `duckdns.org/update?domains=corobook-preprod&token=…&ip=…` call from the box).
3. Confirm it resolves: `dig +short corobook-preprod.duckdns.org` → your server IP.

TLS will not issue until this resolves to the server and 80/443 are reachable.

## 2. Check out the code

```sh
git clone <repo-url> corobook && cd corobook
# or: git pull  to update an existing checkout
```

## 3. Configure the environment

```sh
cd deploy
cp .env.preprod.example .env.preprod
```

Edit `deploy/.env.preprod` and set:

- `APP_HOST` — your DuckDNS host, e.g. `corobook-preprod.duckdns.org`.
- `RAILS_MASTER_KEY` — the contents of `config/master.key`.
- `COROBOOK_NEXT_DATABASE_PASSWORD` — any strong password (used for the Postgres role + the app).
- `MAIL_DOMAIN` / `MAIL_FROM` — optional for preprod. Without a Resend-verified domain,
  confirmation emails won't deliver, but the on-screen fallback link still lets you confirm
  accounts (see `docs/mail-setup.md`).

`deploy/.env.preprod` is gitignored — it holds secrets, keep it on the server only.

## 4. Build and start

```sh
# from deploy/
docker compose --env-file .env.preprod -f docker-compose.preprod.yml up -d --build
```

This starts four services:

| Service    | What it does                                                            |
|------------|-------------------------------------------------------------------------|
| `postgres` | Postgres 16, data persisted in the `pg_data` volume.                    |
| `web`      | The app (production image). First boot runs `db:prepare` (creates the 4 prod DBs) then serves. |
| `worker`   | Solid Queue worker — processes `deliver_later` mail jobs.               |
| `caddy`    | Reverse proxy; obtains + renews the Let's Encrypt cert for `APP_HOST`.  |

## 5. Verify

```sh
docker compose --env-file .env.preprod -f docker-compose.preprod.yml ps      # all healthy/up
docker compose --env-file .env.preprod -f docker-compose.preprod.yml logs -f caddy   # cert issued?
curl -I https://corobook-preprod.duckdns.org/up    # expect HTTP/2 200
```

Then open `https://<APP_HOST>/` — the public landing page. Create an account; since mail may not
deliver on preprod, confirm via the on-screen fallback link (or `docker compose … logs web` shows
the letter_opener-style output is dev-only — on preprod use the fallback link shown after signup).

## Updating preprod

```sh
git pull
cd deploy
docker compose --env-file .env.preprod -f docker-compose.preprod.yml up -d --build
```

`db:prepare` on boot applies any new migrations idempotently.

## Teardown / reset

```sh
# stop (keep data)
docker compose --env-file .env.preprod -f docker-compose.preprod.yml down
# stop AND wipe the database + issued certs (destructive)
docker compose --env-file .env.preprod -f docker-compose.preprod.yml down -v
```

## Notes

- **TLS**: Caddy stores certs in the `caddy_data` volume, so restarts don't re-request them
  (avoids Let's Encrypt rate limits). Don't `down -v` casually in a loop.
- **SSL redirects**: the app runs with `assume_ssl`/`force_ssl`; Caddy terminates TLS and proxies
  plain HTTP to `web:80`, which is why `assume_ssl` is on (no redirect loop).
- **DuckDNS + subdomain login**: on `x.duckdns.org` the app reads `x` as a "subdomain"; since no
  church claims it, login falls back to the normal church picker — harmless.
- This is **preprod**, not production hardening: single box, no backups/offsite, self-contained
  Postgres. Add those before calling it production.
