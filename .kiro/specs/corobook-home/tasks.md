# Home Page — Tasks

Implements `corobook-home/{requirements,design}.md` (revised after the pre-implementation
critique). Ordered per design §7: framework → data-integrity fixes → correct data + redirects
(headless-tested) → the styled view (screenshot-verified). Branch off `develop`; implement →
test → green → commit per task.

## 1. Framework

- [x] 1.1 Vendor DaisyUI v5: commit `vendor/daisyui/daisyui.css` (pinned) and wire the Tailwind
  entry `app/assets/tailwind/application.css` to `@import` it after `@import "tailwindcss"`.
  Rebuild with `bin/rails tailwindcss:build`. Verify the built `tailwind.css` contains DaisyUI
  classes (`.btn-primary`, `.card-body`, `.stat`); suite still green (CSS-only).
  _Requirements: 8.1_ _Design: §1_

## 2. Data-integrity fixes (from the critique)

- [x] 2.1 **Single active session per church (B2).** Migration: partial unique index on
  `live_sessions (church_id) WHERE status = 'active'`; first resolve any pre-existing duplicate
  active sessions (end all but the latest per church). Add a `LiveSession` uniqueness validation
  (`church_id` scoped to active) so a second launch fails cleanly. Tests: a church cannot have
  two active sessions (model validation + DB index both block it); `launch` on a church that
  already has one is rejected/handled, not a raw index error.
  _Requirements: 3.4_ _Design: §3a_
- [x] 2.2 **Usage report admin gate (B3).** Change `ReportsController` from `require_editor` to
  `require_admin`. Request test: an admin gets the CSV; an **editor GET of `/reports/usage` is
  denied** (not just tile-hidden).
  _Requirements: 4.2, 4.3_ _Design: §2_

## 3. Controller, route, data (no styling yet)

- [x] 3.1 Add `root "home#show"` (BEFORE changing the redirect, so `root_path` resolves — H5);
  add `HomeController#show` (require_sign_in, church-scoped): `@active_session`, `@hero_set`
  (via `HeroSet`), `@recent_sets` (≤5, `service_date DESC NULLS LAST`), `@counts` (songs,
  reusable slides, sets). Change `SessionsController#after_sign_in_path` `login_path` → `root_path`.
  Minimal view stub. Tests: signed-out `/` → login; signed-in `/` → 200 with church name;
  sign-in lands on `/`.
  _Requirements: 1.1, 1.2, 1.3, 2.1_ _Design: §2_
- [x] 3.2 Implement `HeroSet.for(church)`: nearest upcoming by `service_date`, else most recent,
  else nil; church-scoped. Unit tests: upcoming chosen; fallback to most recent; nil for empty
  church; never another church's set.
  _Requirements: 3.1, 1.4_ _Design: §3_
- [x] 3.3 Integration tests for gating + counts + scope: editor does NOT see the usage-report
  tile while admin does; `@counts` match seeded data (slides = reusable-library only); no
  cross-church datum appears.
  _Requirements: 4.2, 4.4, 6.1, 1.4_ _Design: §2_

## 4. View (DaisyUI components)

- [x] 4.1 Build the home view, light theme: `navbar` (church name + user/role + sign out); hero
  `card` with ALL states — **Go Live** (shown only when no active session AND hero has ≥1 item),
  **Resume** (`btn-primary`, when an active session exists), **itemless-set** prompt (add items,
  no Go Live — §3.7), **past-set** "Past service" badge (§3.6), and the no-sets empty state with
  **New Set**; quick-action tiles (`grid grid-cols-2 md:grid-cols-4`), the usage-report tile
  rendered only for admins (no Church Settings tile — B1); recent-sets list; library `stat`s
  linking to each index + a song-search `input`. Responsive, no horizontal scroll on phone.
  _Requirements: 2.2, 3.2–3.7, 4.1, 4.5, 5.1, 5.2, 6.1, 6.2, 8.3_ _Design: §4, §5_
- [x] 4.2 System test of the headline path: sign in → land on `/` → hero shows the seeded next
  Set → click **Go Live** → arrive at the operator. Plus: with an active session seeded, hero
  shows **Resume** and no Go Live; an itemless hero set shows no Go Live. Screenshot the running
  Docker app; spot-check hero-button + stat-link contrast (swap any failing variant — H3/H4).
  _Requirements: 1.3, 3.3, 3.4, 3.7, 8.2_ _Design: §4, §6_

## 5. Verification

- [x] 5.1 Full suite green (`bin/rails test` + `test:system`), Brakeman clean. Confirm: the login
  redirect no longer loops to `/login`; the projector/musician/operator surfaces are unaffected
  by the DaisyUI addition; the single-active-session index holds; an editor is denied
  `/reports/usage`.
  _Requirements: all_ _Design: §5, §6_
