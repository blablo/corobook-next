# User Invitations — Design

Implements `user-invitations/requirements.md`. Adds an `Invitation` model, an `InvitationsMailer`,
an admin **Team** surface (members + pending invites) and a public **accept** flow, layered on the
existing `User` / `Church` models and the `Current`-based auth concerns. Multi-tenant throughout:
every admin action roots at `Current.church`; the accept flow is tenant-resolved **by token**, not
by session.

Stack: Rails 8 + Hotwire, importmap/no-build, Tailwind v4 + DaisyUI v5, ActionMailer (configured;
dev `default_url_options` = localhost:3000, prod host set in `production.rb`). No new JS build.

## 1. Data model

### 1.1 `invitations` table (new migration)
```ruby
create_table :invitations do |t|
  t.references :church, null: false, foreign_key: true
  t.references :invited_by, null: false, foreign_key: { to_table: :users }
  t.citext  :email,       null: false          # match users.email (citext)
  t.string  :role,        null: false, default: "editor"
  t.string  :token_digest, null: false         # SHA-256 of the raw token; raw never stored
  t.datetime :expires_at, null: false
  t.datetime :accepted_at                       # null = pending
  t.timestamps
end
add_index :invitations, :token_digest, unique: true
# one PENDING invite per (church, email): partial unique index on not-yet-accepted rows
add_index :invitations, [:church_id, :email],
          unique: true, where: "accepted_at IS NULL", name: "index_pending_invitations"
add_check_constraint :invitations,
  "role::text = ANY (ARRAY['admin'::text, 'editor'::text])", name: "invitations_role_check"
```
Notes:
- **Token is stored as a digest** (Req 6.1). The raw URL-safe token is generated at create/refresh
  time, returned to the controller to build the link + email, and never persisted in plaintext.
  Lookup on accept hashes the path token and finds by `token_digest`.
- The **partial unique index** (`WHERE accepted_at IS NULL`) enforces D-U6 at the DB level: at most
  one *pending* invite per church+email, while allowing historical accepted rows to accumulate.

### 1.2 `Invitation` model
```ruby
class Invitation < ApplicationRecord
  belongs_to :church
  belongs_to :invited_by, class_name: "User"

  enum :role, { admin: "admin", editor: "editor" }, validate: true
  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  EXPIRY = 14.days

  attr_reader :raw_token               # present only on the instance that minted it

  scope :pending, -> { where(accepted_at: nil) }

  def pending?  = accepted_at.nil?
  def expired?  = expires_at.present? && expires_at.past?
  def acceptable? = pending? && !expired?

  # mint/refresh a token + expiry; call before save on create and on resend
  def regenerate_token!
    @raw_token = SecureRandom.urlsafe_base64(32)        # ~192 bits
    self.token_digest = self.class.digest(@raw_token)
    self.expires_at   = EXPIRY.from_now
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)
  def self.find_acceptable_by_token(raw)
    find_by(token_digest: digest(raw))&.then { |i| i.acceptable? ? i : nil }
  end
end
```

### 1.3 `User` / `Church` additions
```ruby
# Church
has_many :invitations, dependent: :destroy
def admins = users.where(role: "admin")
def only_admin? (u) = admins.count == 1 && admins.exists?(id: u.id)   # helper for last-admin guard

# User — no schema change; role enum (admin/editor) already exists.
```

## 2. Routing & controllers

```ruby
# config/routes.rb
resource  :team, only: [:show], controller: "team"            # GET /team (admin surface)
resources :members, only: [:update, :destroy]                 # PATCH/DELETE /members/:id (role, remove)
resources :invitations, only: [:create, :destroy] do
  member { post :resend }                                     # POST /invitations/:id/resend
end
# public accept flow (token in path, no session needed)
get  "invitations/:token/accept" => "invitation_acceptances#show",   as: :accept_invitation
post "invitations/:token/accept" => "invitation_acceptances#create"
```

### 2.1 `TeamController` (admin)
- `before_action :require_admin`.
- `show`: `@members = church_scope(:users).order(:role, :email)`;
  `@invitations = church_scope(:invitations).pending.order(created_at: :desc)`;
  `@invitation = Invitation.new` for the form.

### 2.2 `InvitationsController` (admin)
- `before_action :require_admin`.
- `create` (Req 2.1–2.5):
  1. Normalize email. If `church_scope(:users).exists?(email:)` → reject "already a member" (2.2).
  2. Find existing pending invite for `(church, email)`; if present, treat as **refresh** (2.3).
  3. Build/assign `role`, `invited_by: current_user`, `church: current_church`; `regenerate_token!`.
  4. `save` inside a transaction; on `RecordInvalid`/`RecordNotUnique` → re-render team with errors.
  5. **After commit**, `InvitationsMailer.invite(invitation, raw_token).deliver_later` wrapped so a
     delivery/config error is rescued and logged (D-U10); store the accept URL in flash for the
     on-screen fallback.
- `resend` (5.2): load in church, `regenerate_token!`, save, re-deliver, confirm.
- `destroy` (5.3): load pending invite in church, delete, confirm. (Deleting voids the token.)

### 2.3 `MembersController` (admin)
- `before_action :require_admin`; `find_in_church(:users, params[:id])`.
- `update` (5.4, 5.6): change role; **before demoting admin→editor**, guard
  `current_church.only_admin?(member)` → block with "A church must have at least one admin".
- `destroy` (5.5, 5.6): same last-admin guard, then destroy the user. Disallow removing yourself if
  you are the last admin; allow self-removal otherwise.

### 2.4 `InvitationAcceptancesController` (public — NO church session required)
- **No** `require_sign_in` / `require_admin`. Tenancy comes from the **token**, not `Current`.
- `show` (Req 4.1, 4.2): `inv = Invitation.find_acceptable_by_token(params[:token])`. If nil →
  render the generic "no longer valid" page (status 410 for expired/used, 404 for unknown — both
  render the same neutral template; do not disclose which). Else render accept form with
  `inv.church.name` and `inv.email` read-only.
- `create` (Req 4.3–4.6): re-resolve the token (guard against race/expiry between GET and POST).
  In a transaction:
  - If `inv.church.users.exists?(email: inv.email)` → 4.5 graceful "already have an account".
  - Build `inv.church.users.new(email: inv.email, role: inv.role, password:, password_confirmation:)`.
  - On save, set `inv.accepted_at = Time.current` and save (consumes the pending index slot).
  - `sign_in(user)` and redirect to `root_path` with a welcome notice. `sign_in` already
    `reset_session`s, which also handles the already-signed-in case (4.6).
  - On invalid password → re-render the accept form (token not consumed, 4.4).

### 2.5 Tenancy & safety mapping
- Admin controllers use `church_scope` / `find_in_church` exactly like existing controllers →
  cross-church ids 404 (Req 1.4).
- The accept controller is the one place that reads data **without** a session; it is safe because
  the token is a ≥192-bit single-use secret and the controller never lists or echoes anything but
  the single resolved invite's church name + email (Req 4.2, 6.1).

## 3. Mailer

```ruby
class InvitationsMailer < ApplicationMailer
  # raw_token passed explicitly — Current is unset on the mailer path (Authentication note).
  def invite(invitation, raw_token)
    @invitation = invitation
    @church     = invitation.church
    @inviter    = invitation.invited_by
    @url        = accept_invitation_url(token: raw_token)   # uses default_url_options host
    mail to: invitation.email,
         subject: "You're invited to #{@church.name} on Corobook"
  end
end
```
- Views: `invitations_mailer/invite.html.erb` + `.text.erb` — church, inviter, role, the button/link.
- `deliver_later` (Solid Queue). The controller rescues delivery/enqueue errors so the invite still
  persists (D-U10). URL host is the env `default_url_options`, never `request`/`Current`.

### 3.1 Delivery configuration (Resend prod, letter_opener dev)

Decision **D-U13**: production sends through **Resend** over SMTP; development previews in the
browser with **letter_opener**; test uses the Rails `:test` delivery method (unchanged). Resend's
free tier (3,000/mo, 100/day) covers church invite volume; SMTP keeps the app provider-agnostic
(swapping to SES/Brevo later is a config change, no code change).

**Gemfile**
```ruby
group :development do
  gem "letter_opener"            # opens sent mail in the browser instead of delivering
end
# Resend needs no gem for SMTP delivery; the standard :smtp delivery method is used.
```

**`ApplicationMailer`** — set a real default sender (replaces `from@example.com`):
```ruby
default from: ENV.fetch("MAIL_FROM", "Corobook <no-reply@#{ENV.fetch('MAIL_DOMAIN', 'example.com')}>")
```

**Development** (`config/environments/development.rb`) — preview, never actually send:
```ruby
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
# default_url_options host already = localhost:3000 (present today)
```

**Production** (`config/environments/production.rb`) — Resend SMTP:
```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true   # let the controller's rescue log real failures
config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "corobook.example.com"),
                                              protocol: "https" }
config.action_mailer.smtp_settings = {
  address:        "smtp.resend.com",
  port:           587,
  user_name:      "resend",                          # Resend's SMTP username is literally "resend"
  password:       Rails.application.credentials.dig(:resend, :api_key), # the Resend API key
  authentication: :plain,
  enable_starttls_auto: true
}
```

**Secrets / env (NOT committed):**
- `Rails.application.credentials.resend.api_key` — set via `bin/rails credentials:edit` (encrypted).
- `MAIL_FROM` / `MAIL_DOMAIN` — the verified Resend sender (e.g. `no-reply@yourchurchdomain.org`);
  Resend requires verifying that sending **domain** (SPF/DKIM DNS records) before real delivery.
- `APP_HOST` — the public host used to build absolute accept URLs in prod.

**Operator setup (documented in the PR, done by a human — not the agent):** create a Resend
account, add + verify the sending domain (add the SPF/DKIM/return-path DNS records Resend shows),
create an API key, then `bin/rails credentials:edit` to store it. Until the domain is verified,
Resend only delivers to the account owner's own address; the on-screen accept-URL fallback (D-U10)
covers that gap. Nothing here is a secret the agent reads or writes — the agent edits config only,
never the credential value.

## 4. Views

- `app/views/team/show.html.erb` — admin Team page:
  - **Invite** form (email + role select) at top; shows flash accept-URL fallback after create.
  - **Members** table: email, role (inline role toggle via `members#update`), Remove button
    (disabled/guarded for the last admin).
  - **Pending invitations** table: email, role, invited-by, "sent / expires", Resend + Revoke.
- `app/views/invitation_acceptances/show.html.erb` — church name, invited email (read-only),
  set-password form (POST to the same token path).
- `app/views/invitation_acceptances/invalid.html.erb` — neutral "this invitation is no longer
  valid" page (shared by unknown/used/expired).
- Nav: add a **Team** link under ADMIN in `shell.html.erb`, visible only when `current_user&.admin?`
  (mirrors the existing ADMIN "Usage report" entry seen in the operator screenshot).

## 5. Edge cases & concurrency
- **Double-accept race**: two POSTs with the same token — the first consumes the pending slot; the
  second re-resolve finds it accepted (`acceptable?` false) → invalid page. The partial unique
  index + `accepted_at` set in the same transaction make this safe.
- **Refresh vs. duplicate**: `create` for an email with a pending invite updates the existing row
  (keeps one pending slot); the partial unique index is the backstop if two admins race (one gets
  `RecordNotUnique` → handled as "refreshed").
- **Expired token opened**: `find_acceptable_by_token` returns nil for expired → invalid page; a
  cron/cleanup of old rows is **out of scope** (expired rows are harmless; token is a digest).
- **Last-admin**: guarded in both `members#update` and `members#destroy` using
  `Church#only_admin?`; also covered by a model-level check so a console/other path cannot bypass.

## 6. Testing strategy
- **Model** (`InvitationTest`): token regen is URL-safe/high-entropy and stored only as digest;
  `acceptable?`/`expired?`; `find_acceptable_by_token` for valid/expired/unknown; role validation;
  partial-unique pending index (second pending insert raises).
- **Request** (`InvitationsControllerTest`, `MembersControllerTest`): admin-only gating (editor →
  redirect, Req 1.2); create (new, already-member, refresh-existing, bad email/role); resend;
  revoke; cross-church id → 404; role change + last-admin guard; member remove + last-admin guard.
- **Request** (`InvitationAcceptancesControllerTest`): valid accept creates church-scoped user +
  consumes token + signs in; invalid/expired/used token → neutral invalid page, no sign-in;
  password mismatch re-renders without consuming; already-a-member on accept → graceful (4.5);
  accept while signed in elsewhere (4.6).
- **Mailer** (`InvitationsMailerTest`): to/subject/body contain church, inviter, role, absolute
  accept URL with the configured host (no `Current`).
- **System** (`team_invitation_test.rb`): admin invites → pending row appears with accept URL;
  resend/revoke update the list; (optionally) follow the accept URL in the same test to set a
  password and land signed in. Screenshot-verify the Team page.
- Keep all existing auth/session/live tests green (the login path is unchanged except the accept
  landing).
