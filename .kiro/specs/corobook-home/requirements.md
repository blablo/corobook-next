# Home Page — Requirements

The authenticated landing page (the first screen after login). Today login redirects back to
`/login` showing "Signed in as…" — a placeholder. This spec defines the real home page: a
**launchpad** whose hero is running the next service, built on **Tailwind v4 + DaisyUI v5**
(loaded via `@import` of a vendored `daisyui.css`, no Node — compatibility verified).

## Decisions (resolved)

- **D-H1 Hero = "Next service → Go Live".** The highest-frequency, highest-urgency action
  (Sunday morning) is front-and-center.
- **D-H2 In-progress sessions resume, never relaunch.** If an active `LiveSession` exists for
  the church, the hero offers **Resume**, not a second launch.
- **D-H3 Role gating.** The **usage report** is admin-only, enforced **server-side** (the
  controller uses `require_admin`), not merely by hiding the tile. Everything else (sets, songs,
  slides, library, search) is available to admin and editor. **Church settings is out of v1** —
  no such controller/route exists yet; it gets its own later spec (see Out of scope).
- **D-H4 No analytics dashboard.** Usage is a CSV export (per the CCLI spec), not charts. The
  home page shows counts and links, not graphs.
- **D-H5 Light theme.** This is an admin screen used in a lit room, not the dark sanctuary
  projector; it uses a light DaisyUI theme, distinct from the projector's hand-written black.

## Requirements

### 1. Route and access
1.1 WHEN a signed-in user visits the root path `/`, THE SYSTEM SHALL render the home page.
1.2 WHEN a signed-out visitor visits `/`, THE SYSTEM SHALL redirect to `/login`.
1.3 WHEN a user signs in successfully, THE SYSTEM SHALL redirect to `/` (replacing the current
    "back to login" placeholder).
1.4 THE SYSTEM SHALL scope every datum on the page to the signed-in user's church (no
    cross-church data), consistent with the tenancy invariant.

### 2. Header / context
2.1 THE SYSTEM SHALL display the church name prominently (the operator must never be unsure
    which of the two churches they are in).
2.2 THE SYSTEM SHALL display the signed-in user's email and role, and a sign-out control.
2.3 THE SYSTEM SHALL NOT offer a church switcher (one user belongs to exactly one church).

### 3. Hero — next service
3.1 THE SYSTEM SHALL select the hero Set as the nearest upcoming Set by `service_date`
    (today or future); IF none is upcoming, THE SYSTEM SHALL fall back to the most recent Set.
3.2 THE SYSTEM SHALL show the hero Set's name, service date, and item count.
3.3 WHEN no active `LiveSession` exists for the church AND the hero Set has at least one item,
    THE SYSTEM SHALL show a prominent **Go Live** action that launches a `LiveSession` for the
    hero Set and opens the operator.
3.4 WHEN an active `LiveSession` exists for the church, THE SYSTEM SHALL instead show a
    **Resume** action that opens that session's operator, AND SHALL NOT offer a second launch
    (D-H2). There SHALL be at most one active session per church — enforced by a DB partial
    unique index + a model validation (see design §3), so Resume is unambiguous.
3.5 IF the church has no Sets at all, THE SYSTEM SHALL show an empty state inviting the user to
    create the first Set, with a **New Set** action.
3.6 WHERE the hero Set is a PAST set (its `service_date` is before today, used as the fallback
    because none is upcoming), THE SYSTEM SHALL label it visibly as a past service so the
    operator does not relaunch a stale set by reflex.
3.7 IF the hero Set has ZERO items, THE SYSTEM SHALL NOT offer Go Live (a session with no items
    is meaningless); it SHALL instead prompt the user to add items to that Set.

### 4. Quick actions
4.1 THE SYSTEM SHALL offer quick actions: New Set, New Song, New Slide, Browse Songs.
4.2 THE SYSTEM SHALL offer a **Usage Report** action to admins only (D-H3).
4.3 THE SYSTEM SHALL enforce the usage-report admin restriction **server-side** (the report
    controller SHALL require admin), so an editor reaching the route directly is denied — hiding
    the tile is defense-in-depth, not the only guard.
4.4 WHERE the signed-in user is an editor (not admin), THE SYSTEM SHALL hide the admin-only
    actions rather than showing a disabled or erroring control.
4.5 THE SYSTEM SHALL NOT offer a Church Settings action in v1 (no such route exists yet).

### 5. Recent / upcoming sets
5.1 THE SYSTEM SHALL list up to the 5 most relevant Sets (upcoming first, then recent), each
    with name, service date, and item count.
5.2 WHEN the user selects a listed Set, THE SYSTEM SHALL open that Set's builder/detail.
5.3 THE SYSTEM SHALL NOT display per-run session history on the home page (that belongs to the
    Set itself).

### 6. Library at a glance
6.1 THE SYSTEM SHALL display counts of songs, **reusable library** text slides, and sets for
    the church, each linking to its index. (The slide count is reusable-library slides only;
    inline one-off slides owned by a Set are not library content and are excluded by design.)
6.2 THE SYSTEM SHALL provide a search entry that jumps into church-scoped song search.

### 7. Scope exclusions (explicitly NOT on the home page)
7.1 THE SYSTEM SHALL NOT render the full song list (that is the library/index page).
7.2 THE SYSTEM SHALL NOT render usage charts or analytics (D-H4).
7.3 THE SYSTEM SHALL NOT render any multi-church or cross-tenant affordance.

### 8. Presentation & accessibility
8.1 THE SYSTEM SHALL build the page with Tailwind + DaisyUI components on a light theme (D-H5).
8.2 THE SYSTEM SHALL aim for WCAG AA contrast on text and interactive controls as a
    **best-effort, spot-checked** standard (matching the rewrite spec's admin NFR; the projector
    remains strict). Build verification SHALL spot-check the hero button and stat links and pick
    DaisyUI variants whose foreground/fill pass; a variant that fails is replaced, not shipped.
8.3 THE SYSTEM SHALL be usable on a phone/tablet width (the leader may open it on a device),
    with the hero and quick actions reachable without horizontal scroll.

## Out of scope / deferred
- **Church settings** (name, CCLI #) — no controller/route exists; its own later spec.
- A notifications/activity feed, a welcome/onboarding tour, and service notes — not v1.
- Reordering or editing Sets inline from the home page (use the Set builder).
