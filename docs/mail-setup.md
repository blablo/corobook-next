# Production mail setup (Resend)

Corobook sends transactional email — **signup confirmation** and **team invitations** — in
production through [Resend](https://resend.com) over SMTP. The application code is already wired;
this runbook covers the account, secret, env, and worker steps needed to make delivery live.

> Development needs none of this: `letter_opener` opens mail in the browser, and the
> confirmation/invitation link is also shown on-screen as a fallback.

---

## What's already configured in the app

- `config/environments/production.rb` — SMTP via `smtp.resend.com:587` (STARTTLS), delivery on,
  `default_url_options.host` from `APP_HOST`.
- `app/mailers/application_mailer.rb` — `from:` built from `MAIL_FROM` / `MAIL_DOMAIN`.
- Mailers: `RegistrationsMailer#confirm`, `InvitationsMailer#invite`.
- Delivery is **best-effort** — signup/invite/resend wrap delivery in a rescue, so a mail outage
  never 500s the user-facing request.
- Jobs run via **Solid Queue** (`deliver_later`), so a worker must be running (see step 5).

You do **not** need to change any of the above. The steps below are account + ops only.

---

## 1. Create the Resend account and verify your sending domain

1. Sign up at <https://resend.com>.
2. Add your sending domain (the one in `MAIL_DOMAIN`, e.g. `corobook.app`).
3. Add the **SPF** and **DKIM** DNS records Resend shows you, to that domain's DNS.
4. Wait for Resend to show the domain as **Verified**. Unverified domains are rejected at send.

An unverified domain is the most common reason "mail silently doesn't arrive" — verify first.

## 2. Create the API key

In Resend → **API Keys** → create a key with **Sending** permission. Copy it once
(`re_xxxxxxxx…`); you can't read it again later.

## 3. Store the key in Rails encrypted credentials (NOT env, NOT the repo)

```sh
bin/rails credentials:edit
```

Add:

```yaml
resend:
  api_key: re_xxxxxxxxxxxxxxxxxxxxxxxx
```

Save and close. This writes `config/credentials.yml.enc` (encrypted, committed) and requires the
`RAILS_MASTER_KEY` (or `config/master.key`) to decrypt in production. Confirm it's readable:

```sh
RAILS_ENV=production bin/rails runner \
  'puts Rails.application.credentials.dig(:resend, :api_key) ? "KEY_PRESENT" : "KEY_MISSING"'
```

## 4. Set the production environment variables

See `.env.example`. In your production host's environment set:

| Var           | Example                              | Purpose                                            |
|---------------|--------------------------------------|----------------------------------------------------|
| `APP_HOST`    | `corobook.app`                       | Host for absolute links in emails (HTTPS).         |
| `MAIL_DOMAIN` | `corobook.app`                       | Must be a **Resend-verified** domain.              |
| `MAIL_FROM`   | `Corobook <no-reply@corobook.app>`   | The `From` header on all outgoing mail.            |
| `RAILS_MASTER_KEY` | (your master key)               | Decrypts credentials (holds the Resend API key).   |

## 5. Run the Solid Queue worker

`deliver_later` enqueues to Solid Queue, so a worker must process the jobs:

```sh
RAILS_ENV=production bin/jobs
```

Run it as a managed process (systemd unit, container sidecar, Procfile `worker:` line, etc.)
alongside the web process. Without it, confirmation/invitation emails are queued but never sent.

## 6. Smoke test

With the above in place, from a production console:

```sh
RAILS_ENV=production bin/rails runner '
  u = User.where.not(confirmed_at: nil).first
  RegistrationsMailer.confirm(u, "smoke-test-token").deliver_now
'
```

`deliver_now` bypasses the queue so any SMTP/credential/domain error surfaces immediately in the
console. Expect a 200-level Resend response and the email in the destination inbox. Then do a real
end-to-end: sign up a test church and confirm from the emailed link.

---

## Switching providers later

The app is provider-agnostic: it only speaks SMTP. To move to SES / Postmark / Brevo, change the
`smtp_settings` block in `config/environments/production.rb` (address, port, user, and the
credentials key the password reads) — no application or mailer code changes.

## Troubleshooting

- **`KEY_MISSING`** — the credentials entry isn't there or `RAILS_MASTER_KEY` is wrong.
- **Mail queued but never arrives** — the Solid Queue worker (step 5) isn't running.
- **Resend rejects the send** — the `MAIL_DOMAIN` isn't verified, or `MAIL_FROM` uses a different
  domain than the verified one.
- **Links point at the wrong host** — `APP_HOST` is unset/wrong (links fall back to the default).
