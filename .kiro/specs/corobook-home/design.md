# Home Page — Design

Implements `corobook-home/requirements.md`. A launchpad whose hero runs the next service,
built on Tailwind v4 + DaisyUI v5. This is the first use of DaisyUI, so §1 sets the framework
up once for the whole app.

## 1. DaisyUI setup (compatibility verified)

Tailwind is **v4** (`tailwindcss-ruby 4.3.3`, CSS-first config, no `tailwind.config.js`, no
`package.json`). DaisyUI v5 ships a single `daisyui.css` loadable by Tailwind v4 **without npm**.
Verified locally: `@plugin` fails (expects a JS object); **`@import` of the vendored CSS works**
and compiles the component classes.

- Vendor `vendor/daisyui/daisyui.css` (pinned, committed — it is the dependency, no npm resolves
  it).
- Entry `app/assets/tailwind/application.css`:
  ```css
  @import "tailwindcss";
  @import "../../../vendor/daisyui/daisyui.css";
  ```
- Build with the existing `bin/rails tailwindcss:build` / `tailwindcss:watch`; CI already runs
  the build. No toolchain change.
- **Theme:** use a light DaisyUI theme for admin surfaces (D-H5). The projector keeps its
  hand-written black CSS (§5 of the rewrite design) and does NOT adopt DaisyUI — the two
  surfaces are deliberately different.

## 2. Routing & controller

```ruby
# routes.rb
root "home#show"                         # replaces the absent root
# sessions#create after_sign_in_path -> root_path (was login_path placeholder)
```

`HomeController#show` (authenticated, church-scoped via `Current.church`, both roles):

```ruby
class HomeController < ApplicationController
  before_action :require_sign_in
  def show
    @active_session = church_scope(:live_sessions).find_by(status: "active") # ≤1 by §3 index
    @hero_set       = HeroSet.for(Current.church)           # §3
    @recent_sets    = Current.church.service_sets
                        .order(Arel.sql("service_date DESC NULLS LAST, name ASC")).limit(5)
    @counts = {
      songs: Current.church.songs.count,
      slides: Current.church.text_slides.where(reusable: true).count, # library slides only
      sets: Current.church.service_sets.count
    }
  end
end
```

Role gating: the only admin-only action is **Usage Report**, hidden in the view with
`<% if current_user.admin? %>` AND enforced server-side — **`ReportsController` is changed from
`require_editor` to `require_admin`** (this spec owns that change; without it the hidden tile is
the only guard and an editor could GET `/reports/usage` directly). **Church Settings is NOT on
the page** (no such route exists in v1). The admin tile hides rather than disables (requirements
§4.4); the server guard is defense-in-depth.

## 3. Hero-set selection

A small query object keeps the "upcoming else most recent" rule testable:

```ruby
class HeroSet
  def self.for(church)
    upcoming = church.service_sets.where("service_date >= ?", Date.current)
                     .order(:service_date).first
    upcoming || church.service_sets.order(Arel.sql("service_date DESC NULLS LAST")).first
  end
end
```

Hero render states (requirements §3.3–3.7):
- **active session exists** → DaisyUI `btn btn-primary` **Resume** → `operator_path(@active_session)`.
  (Resume is `btn-primary`, not `btn-warning`: resuming is not a warning, and DaisyUI `warning`'s
  foreground is the variant most likely to fail contrast — H4.)
- **no active session, hero set has ≥1 item** → `btn btn-primary btn-lg` **Go Live** →
  `POST launch_service_set_path(@hero_set)` (the existing launch route) → operator.
- **hero set has 0 items** → no Go Live; a prompt/link to add items to that Set (requirements §3.7).
- **hero set is a past set** (fallback, `service_date < today`) → render a "Past service" badge
  next to the date so the operator does not relaunch a stale set by reflex (requirements §3.6).
- **no sets at all** → an empty-state `card` with a **New Set** `btn btn-primary`.

### 3a. Single active session per church (the "never relaunch" guarantee — B2 fix)

The requirement that Resume is unambiguous and Go Live cannot double-launch needs a real
guarantee, not just a hidden button. The home spec adds it (it was missing from the backend):

- **DB:** a partial unique index `CREATE UNIQUE INDEX … ON live_sessions (church_id) WHERE status
  = 'active'` — Postgres enforces at most one active session per church.
- **Model:** `LiveSession` validates uniqueness of `church_id` scoped to active status, so a
  second `launch` fails cleanly (caught, surfaced) rather than raising a raw index violation.
- Then `@active_session = find_by(status: "active")` returns THE one active session (not an
  arbitrary one of N), and the view's "hide Go Live when active" is backed by the data layer.

Go Live is a `button_to` (POST) shown only when `@active_session` is nil and the hero has items;
with the index above, even a racing double-POST cannot create two active sessions.

## 4. Layout & component mapping

A light page in the `application` layout (the follower layout stays for projector/musician).

```
┌ navbar (DaisyUI `navbar`) ───────────────────────────────┐
│ Corobook · <Church name>        <user email · role> ⌄ ▸ Sign out │
├──────────────────────────────────────────────────────────┤
│  HERO (card, prominent)                                   │
│   “Next service”   <Set name>   <date · N items>          │
│   [ Go Live ]  (or [ Resume ] / empty-state New Set)      │
├───────────────┬───────────────┬──────────────┬───────────┤
│ New Set       │ New Song      │ New Slide     │ Browse    │   quick-action tiles (card/btn)
│ Usage Report* (*admin only — server-side require_admin)   │
├──────────────────────────────────────────────────────────┤
│  Recent sets (list / table)   name · date · N items  → …  │
├──────────────────────────────────────────────────────────┤
│  Library at a glance:  N songs · N slides · N sets        │   DaisyUI `stat`s, each a link
│  [ search songs … ]                                       │
└──────────────────────────────────────────────────────────┘
```

Component mapping: `navbar` (header), `card` (hero + tiles), `btn` + variants (actions),
`stat`/`stats` (counts), `input`/`join` (search), `badge` (item counts, LIVE state). Responsive:
the tile row is a `grid grid-cols-2 md:grid-cols-4`; the hero stacks above it; everything
reachable without horizontal scroll on a phone (requirements §8.3).

## 5. Accessibility

- Light theme chosen to aim for AA contrast on text/controls (requirements §8.2); this is
  **best-effort, spot-checked**, matching the rewrite's admin NFR — NOT a formal AA audit. Build
  verification measures the hero button and stat-link ratios and swaps any DaisyUI variant whose
  foreground/fill fails (which is why Resume is `btn-primary`, not `btn-warning` — H4). The
  projector remains the strict-contrast surface.
- Every action is a real `<a>`/`<button>` (DaisyUI classes on native elements), so keyboard and
  screen-reader behavior is native; no div-buttons.
- The LIVE/Resume state is conveyed by text + a badge, not color alone.

## 6. Tests

- **Request/integration:** signed-out `/` → redirect to login; signed-in → 200 with church name;
  hero shows Go Live when no active session (and hero has items) and Resume when one exists;
  editor does NOT see the usage-report tile AND an editor GET of `/reports/usage` is **denied**
  (B3); counts match seeded data (slides = reusable only); cross-church data never appears.
- **Unit:** `HeroSet.for` picks the nearest upcoming set, falls back to most recent, returns nil
  for an empty church, and is church-scoped. `LiveSession` rejects a second active session for a
  church (uniqueness validation), and the partial unique index blocks it at the DB (B2).
- **Hero edge cases:** an itemless hero set shows no Go Live (§3.7); a past-set fallback shows
  the "Past service" badge (§3.6).
- **System:** sign in → land on home → click Go Live → arrive at the operator (the login
  redirect fix end to end); with an active session seeded, the hero shows Resume and no Go Live.

## 7. Build order (feeds tasks.md)

1. DaisyUI setup (vendor + entry `@import` + rebuild) — proven, lands first.
2. **Single-active-session guarantee (B2):** migration adding the partial unique index on
   `live_sessions(church_id) WHERE status='active'`, plus the `LiveSession` uniqueness
   validation, with model + DB tests. (Backfill note: if seed/dev data already has >1 active
   session for a church, the migration must resolve duplicates first — end all-but-the-latest.)
3. **`ReportsController` → `require_admin` (B3)**, with a request test that an editor is denied.
4. `HomeController` + `root` route + `HeroSet` + the `after_sign_in_path` fix, with request/unit
   tests (no styling yet — correct data and redirects first; add `root` BEFORE the redirect
   change so `root_path` resolves — H5).
5. The view with DaisyUI components (hero states incl. itemless/past-set/Resume, tiles, recent
   sets, stats), then the system test. Screenshot the running app to verify the light launchpad
   and spot-check contrast.
