# User Invitations — Tasks

Implements `user-invitations/{requirements,design}.md`. Ordered backend-first: model + migration,
then the public accept flow and admin management (request-tested), then the mailer and views
(system-tested / screenshot-verified), then edge cases. Every task keeps existing auth/session/live
tests green.

Branch off `develop`; implement → test → green → commit per task. Ships as one branch + one PR
targeting `develop` (repo workflow, Req 6.3). After any model/migration/view change in the dev
container: `docker restart corobook-next-web-1`; rebuild CSS with
`docker exec corobook-next-web-1 bin/rails tailwindcss:build` when styles change.

## 1. Model & migration (no UI yet)

- [ ] 1.1 **Migration + `Invitation` model.** Create the `invitations` table per Design §1.1
  (church ref, invited_by ref → users, citext email, role, token_digest, expires_at, accepted_at,
  timestamps), the unique `token_digest` index, the **partial unique** `index_pending_invitations`
  (`WHERE accepted_at IS NULL`), and the role check constraint. Add the `Invitation` model (§1.2):
  associations, role enum (validated), email normalize + format, `EXPIRY`, `regenerate_token!`,
  `digest`, `find_acceptable_by_token`, `pending?/expired?/acceptable?`, `pending` scope.
  Unit tests: token is URL-safe and ≥128 bits of entropy; raw token never written to `token_digest`
  column verbatim (digest != raw); `expired?`/`acceptable?` boundaries; role validation; a second
  **pending** row for the same (church,email) raises `RecordNotUnique` while an accepted row does
  not block a new pending one.
  _Requirements: 2.1, 6.1, D-U4, D-U6_ _Design: §1.1, §1.2_

- [ ] 1.2 **Church/User helpers.** Add `Church has_many :invitations, dependent: :destroy`,
  `Church#admins`, `Church#only_admin?(user)`. Unit tests: `only_admin?` true only when the church
  has exactly one admin and it is that user; false with two admins or for an editor.
  _Requirements: 5.6, D-U9_ _Design: §1.3_

## 2. Public accept flow (request-tested)

- [ ] 2.1 **Routes + `InvitationAcceptancesController#show`.** Add the accept routes (§2). `show`
  resolves the token via `find_acceptable_by_token`; valid → render accept form (church name +
  read-only email); nil → render neutral `invalid` template (410 expired/used, 404 unknown). No
  auth filters. Request tests: valid pending token renders the form with church+email; unknown →
  neutral invalid (no church disclosed); expired → neutral invalid; already-accepted → neutral
  invalid.
  _Requirements: 4.1, 4.2, 3.2_ _Design: §2.4_

- [ ] 2.2 **`#create` (accept).** Re-resolve token; transaction: already-member → graceful
  "already have an account" (no 500); else create `church.users.new(email, role, password,
  password_confirmation)`, set `accepted_at`, save both, `sign_in(user)`, redirect to `root_path`
  with welcome. Invalid/mismatched password → re-render form, token NOT consumed. Request tests:
  valid accept creates a church-scoped user with the invited role, consumes the token (second
  accept → invalid), and signs in; password mismatch/short re-renders and creates nothing;
  already-member on accept is graceful (4.5); accept while signed in as another church user still
  creates+signs in the new user (4.6).
  _Requirements: 4.3, 4.4, 4.5, 4.6, 6.2_ _Design: §2.4_

## 3. Admin management (request-tested)

- [ ] 3.1 **`TeamController#show` + route + nav.** `require_admin`; load members and pending invites
  scoped to `Current.church`; add the ADMIN **Team** nav link (admin-only). Request tests: admin
  sees members + pending invites of own church only; editor → redirect (1.2); anonymous → login
  (1.3); invites/members of another church never appear.
  _Requirements: 1.1, 1.2, 1.3, 5.1_ _Design: §2.1, §4_

- [ ] 3.2 **`InvitationsController#create/#resend/#destroy`.** `require_admin`. `create`:
  already-member reject (2.2); refresh existing pending (2.3); validate email/role (2.4); mint
  token, `invited_by`, save; rescue mail errors, stash accept URL in flash (2.5). `resend`: regen +
  re-deliver (5.2). `destroy`: void pending (5.3). Request tests: create new pending; create for a
  member rejected; create for existing pending refreshes (same row, new expiry, still one pending);
  blank/bad email + bad role rejected; resend regenerates token + expiry; revoke removes the row
  and its token stops accepting; cross-church invitation id → 404.
  _Requirements: 2.1–2.5, 5.2, 5.3, 1.4_ _Design: §2.2_

- [ ] 3.3 **`MembersController#update/#destroy` with last-admin guard.** `require_admin`;
  `find_in_church(:users, id)`. `update` toggles role; `destroy` removes member. Both block the
  **last admin** (demote or remove) via `Church#only_admin?` with the clear message; a model-level
  check backs it. Request tests: role change persists; demoting the sole admin blocked; removing
  the sole admin blocked; demoting/removing a non-last admin allowed; cross-church member id → 404.
  _Requirements: 5.4, 5.5, 5.6, 1.4, D-U9_ _Design: §2.3_

## 4. Mailer (mailer-tested)

- [ ] 4.1 **Delivery config: Resend (prod) + letter_opener (dev).** Add `letter_opener` to the
  `:development` group (bundle). Set `ApplicationMailer` default `from` to `MAIL_FROM`/`MAIL_DOMAIN`
  (replacing `from@example.com`). Development: `delivery_method = :letter_opener`. Production:
  `delivery_method = :smtp` with Resend `smtp_settings` (`smtp.resend.com:587`, user `"resend"`,
  password from `credentials.dig(:resend, :api_key)`, STARTTLS), `raise_delivery_errors = true`,
  and `default_url_options` host from `APP_HOST` over https. Test env keeps `:test`. Verify the
  test suite still captures mail via `ActionMailer::Base.deliveries` (no real send in test). Add a
  short "Email setup" note to the PR: create Resend account, verify sending domain (SPF/DKIM),
  create API key, `bin/rails credentials:edit`. Do NOT commit any key.
  _Requirements: 2.5, 3.1, D-U10, D-U13_ _Design: §3.1_

- [ ] 4.2 **`InvitationsMailer#invite` + templates.** Accept `(invitation, raw_token)`; build the
  absolute accept URL from `default_url_options` (NOT `Current`/`request`); html + text templates
  naming church, inviter, role, and the link. Wire `deliver_later` from the controller behind a
  rescue (§2.2 step 5). Mailer tests: `to` = invitee, subject names the church, body contains the
  inviter, the role, and the absolute accept URL with the configured host.
  _Requirements: 3.1, 3.2, 2.5, D-U10_ _Design: §3_

## 5. Views & system verification

- [ ] 5.1 **Team page view.** `team/show.html.erb`: invite form (email + role), members table with
  inline role toggle + guarded Remove, pending-invites table with Resend + Revoke, and the
  on-screen accept-URL fallback flash. Themed with the existing admin styles. Rebuild CSS; restart.
  _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 2.5_ _Design: §4_

- [ ] 5.2 **Accept + invalid views.** `invitation_acceptances/show.html.erb` (church name, read-only
  email, set-password form) and `invitation_acceptances/invalid.html.erb` (neutral message).
  _Requirements: 4.1, 4.2, 4.4_ _Design: §4_

- [ ] 5.3 **System test + screenshot.** `test/system/team_invitation_test.rb`: admin signs in,
  invites an email with a role, sees the pending row and the accept URL; resend and revoke update
  the list; follow the accept URL, set a password, and land signed in as the new member. Capture a
  screenshot of the Team page. (Local Chrome crashes — rely on CI for the system run.)
  _Requirements: 1.1, 2.1, 4.3, 5.1, 5.2, 5.3_ _Design: §6_

## 6. Finalize

- [ ] 6.1 **Full suite + Rubocop + PR.** Run the unit/integration suite and the changed-file
  Rubocop; ensure existing auth/session/live tests stay green. Open the PR against `develop` with a
  summary, the requirements/design/tasks links, and the manual accept-URL fallback note.
  _Requirements: 6.3_
