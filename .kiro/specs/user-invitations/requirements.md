# User Invitations — Requirements

A church today is seeded with users out of band; there is no way for a church to grow its own
team. This spec adds **email invitations**: a church **admin** invites a person by email to join
*their* church with a chosen role, the person receives a link, follows it, sets a password, and
lands signed in. It also adds the surrounding team-management surface an admin needs: see who is
in the church, see pending invitations, resend or revoke a pending one, change a member's role,
and remove a member.

This is a **multi-tenant, per-church** feature. Everything is scoped to the inviter's church
(`TenantScoped`): an admin can never invite into, or see members of, another church. It reuses the
existing `User` model (`has_secure_password`, `role` enum admin/editor, unique `(church_id,
email)`), the `Current`-based `Authentication`/`Authorization` concerns, and ActionMailer (already
configured). It adds one new model (`Invitation`), one mailer, and the member/invite UI.

## Decisions (resolved)

- **D-U1 Admin-only invites.** Only an **admin** may invite, resend, revoke, change roles, or
  remove members. `editor` is a content role with no team-management power. This matches the
  existing `require_admin` gate; no new role tier is introduced for *this* capability.
- **D-U2 No self-service signup.** There is still no public "create an account / create a church"
  flow. The **only** way to become a user of a church is (a) seeded, or (b) accepting an
  invitation. The login page is unchanged except for the accept flow landing a new user signed in.
- **D-U3 Invite by email + role.** An invitation carries the **invitee email** and the **role**
  (admin or editor) the invitee will receive on acceptance. Role is chosen at invite time and may
  be changed while the invite is still pending (via revoke + re-invite, or a role edit — see 5.x).
- **D-U4 Token-based, expiring, single-church link.** Each invitation has a **long random token**
  (URL-safe, single-use) and belongs to exactly one church. The accept link is
  `/invitations/:token/accept`. The token is the only credential needed to reach the accept page;
  **no church picker** is shown on accept (the church is fixed by the token). Tokens **expire**
  after **14 days**; an expired or already-used token shows a clear "this invitation is no longer
  valid" page, not a 500 and not a silent sign-in.
- **D-U5 Set-password-on-accept.** The invitee has no password until they accept. The accept page
  asks them to **set a password** (with confirmation). On success the invitation is marked
  accepted, the `User` row is created (or completed) with the invited role, and the invitee is
  **signed in** and redirected to the church home. The invitation token is consumed (cannot be
  reused).
- **D-U6 One pending invite per (church, email).** A church cannot have two simultaneously
  **pending** invitations for the same email. Re-inviting an email that already has a pending
  invite **refreshes** it (new token + new expiry, re-sends the mail) rather than creating a
  duplicate. An email that is **already a member** of the church cannot be invited (clear message).
- **D-U7 Invitation ≠ User until accepted.** A pending invitation does **not** create a `User`
  row and does **not** let that email sign in. A pending invite for an email that is not yet a
  user is the normal case; the `User` is created only at acceptance. This keeps the login path and
  the unique `(church_id, email)` index clean (no half-created, passwordless users).
- **D-U8 Email across churches is allowed.** The same email address may be a member of (or invited
  to) **different** churches independently; uniqueness is per church, as today. The accept flow
  creates a church-scoped `User`; it does not merge or link identities across churches.
- **D-U9 An admin cannot lock the church out.** A church must always retain **at least one admin**.
  The system blocks the last admin from (a) being demoted to editor, (b) being removed, and (c)
  revoking is unaffected (invites are not members). An admin **may** remove/demote *other* admins
  and themselves **only if another admin remains**.
- **D-U10 Mailer is best-effort; the invite is authoritative.** Creating the invitation and its
  token is the source of truth; sending the email is a side effect. If mail delivery is not
  configured or fails, the invitation still exists and the admin sees the **accept URL** on screen
  to share manually (dev has no real SMTP). Delivery errors never roll back the invite.
- **D-U11 No viewer/read-only role in this spec.** Roles remain exactly **admin** and **editor**.
  A read-only "viewer" tier is explicitly **out of scope** here (the Set Builder spec references a
  "viewer" aspirationally, but it does not exist in the model and this spec does not add it).
- **D-U12 Minimal audit.** An invitation records **who** created it (`invited_by` → User) and the
  timestamps (`created_at`, `accepted_at`, `expires_at`). Full audit logging is out of scope.
- **D-U13 Email delivery: Resend (prod) + letter_opener (dev).** Production delivers invitation
  mail through **Resend over SMTP** (free tier 3,000/mo, 100/day — ample for invites); the Resend
  API key lives in Rails encrypted credentials, never in the repo. Development uses **letter_opener**
  to preview mail in the browser instead of sending; test keeps the `:test` delivery method. SMTP
  (not a provider SDK) keeps delivery provider-agnostic — swapping to SES/Brevo later is a config
  change, not a code change. This does not alter the mailer's content or the D-U10 best-effort
  rule: a missing key or unverified domain still leaves the invite persisted with the on-screen
  accept-URL fallback.

## Requirements

### 1. Access and scope
1.1 WHEN a signed-in **admin** opens the team page, THE SYSTEM SHALL render the church's members
    list and its pending invitations, scoped to the admin's own church only.
1.2 WHEN a signed-in **editor** attempts to open the team page or any invite/member-management
    action, THE SYSTEM SHALL deny the request (redirect to login with "You are not allowed to do
    that."), exactly as `require_admin` does today.
1.3 WHEN an unauthenticated visitor requests the team page or any member-management action, THE
    SYSTEM SHALL redirect to the login page with "Please sign in."
1.4 WHERE an admin references an invitation or member by id, THE SYSTEM SHALL resolve it only
    within the admin's own church; a cross-church id SHALL raise RecordNotFound → 404 (never 403,
    per the tenant non-disclosure rule).

### 2. Creating an invitation
2.1 WHEN an admin submits an invite with a valid email and a role of `admin` or `editor`, THE
    SYSTEM SHALL create a pending `Invitation` for that email in the admin's church, with a
    single-use URL-safe token, an `expires_at` 14 days out, and `invited_by` = the current admin.
2.2 WHEN an admin submits an invite for an email that is **already a member** of the church, THE
    SYSTEM SHALL reject it with a clear message ("That person is already a member") and create no
    invitation.
2.3 WHEN an admin submits an invite for an email that already has a **pending** invitation in the
    church, THE SYSTEM SHALL refresh that invitation (new token, new 14-day expiry) and re-send the
    email, rather than creating a second pending invitation (one pending per church+email, D-U6).
2.4 WHEN an admin submits an invite with a blank or malformed email, or a role outside
    {admin, editor}, THE SYSTEM SHALL reject it with a validation message and create no invitation.
2.5 WHEN an invitation is created or refreshed, THE SYSTEM SHALL attempt to deliver an invitation
    email containing the accept link, AND SHALL still succeed (invitation persisted) even if
    delivery raises; the admin SHALL be shown the accept URL on screen as a fallback (D-U10).

### 3. The invitation email and link
3.1 THE invitation email SHALL address the invitee, name the church and the inviting person, state
    the role, and contain the absolute accept URL `/invitations/:token/accept` built with the app's
    configured host (not from `Current`, which is unset on the mailer path).
3.2 THE accept link SHALL be the only credential required to reach the accept page; it SHALL NOT
    require the invitee to already have an account or to know the church.

### 4. Accepting an invitation
4.1 WHEN a visitor opens a valid, pending, unexpired accept link, THE SYSTEM SHALL render an
    accept page showing the church name and the invited email (read-only) and a **set-password**
    form (password + confirmation). No church picker is shown.
4.2 WHEN a visitor opens an accept link whose token is unknown, already accepted, or expired, THE
    SYSTEM SHALL render a clear "this invitation is no longer valid" page (HTTP 404/410 as
    appropriate), SHALL NOT sign anyone in, and SHALL NOT reveal any church/member details beyond
    the generic message.
4.3 WHEN the invitee submits the accept form with a valid matching password, THE SYSTEM SHALL
    create the church-scoped `User` with the invited email and role, mark the invitation
    `accepted_at` and consume its token, sign the invitee in, and redirect to the church home with
    a welcome notice — all atomically (either the user is created and the invite consumed, or
    neither).
4.4 WHEN the invitee submits a blank/mismatched/too-short password, THE SYSTEM SHALL re-render the
    accept form with a validation message and SHALL NOT create a user or consume the token.
4.5 WHERE the email became a member of the church between the invite being sent and accepted (e.g.
    seeded in the meantime), THE SYSTEM SHALL fail gracefully on accept ("You already have an
    account for this church — please sign in") rather than violating the unique `(church_id,email)`
    index with a 500.
4.6 WHEN an accept link is opened while the visitor is already signed in (any church), THE SYSTEM
    SHALL still render the accept flow for the invited email (the invite is church-scoped and
    independent of the current session), and on acceptance SHALL sign them in as the newly created
    church-scoped user.

### 5. Managing members and pending invites
5.1 WHEN an admin views the team page, THE SYSTEM SHALL list current members (email + role) and
    pending invitations (email, role, invited-by, sent/expiry) separately and clearly labeled.
5.2 WHEN an admin resends a pending invitation, THE SYSTEM SHALL refresh its token + expiry and
    re-deliver the email (same as 2.3's refresh), and confirm on screen.
5.3 WHEN an admin revokes a pending invitation, THE SYSTEM SHALL delete/void it so its token no
    longer accepts, and remove it from the pending list.
5.4 WHEN an admin changes a member's role between admin and editor, THE SYSTEM SHALL persist the
    change, subject to the last-admin guard (5.6).
5.5 WHEN an admin removes a member, THE SYSTEM SHALL delete that `User`, subject to the last-admin
    guard (5.6); removing a user SHALL follow the church's existing `dependent: :destroy` only for
    the user row itself (members do not own songs/sets — those belong to the church).
5.6 WHILE a church has exactly one admin, THE SYSTEM SHALL block demoting or removing that last
    admin, returning a clear message ("A church must have at least one admin"), so no action can
    leave a church with zero admins (D-U9).

### 6. Non-functional
6.1 Tokens SHALL be generated from a cryptographically secure source, be URL-safe, and have enough
    entropy to resist guessing (≥ 128 bits); they SHALL be stored so a leaked database row does not
    trivially expose a usable token in plaintext logs (store digest or at minimum never log it).
6.2 All member-management and invite actions SHALL be CSRF-protected form POST/PATCH/DELETE (Rails
    default), not GET side effects; the accept **page** is a GET, acceptance is a POST/PATCH.
6.3 The feature SHALL ship behind the repo workflow: one branch + one PR targeting `develop`, with
    model/request/system tests green and Rubocop clean.
