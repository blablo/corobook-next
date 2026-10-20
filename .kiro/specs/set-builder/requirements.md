# Set Builder — Requirements

The **Set Builder** is the screen where an editor assembles a service program: pick songs and
slides from the church library, arrange them in play order, and launch the set live. Today a Set
exists as data (`ServiceSet` + `SetItem`, with `add_item` / `remove_item` / `reorder` already
implemented server-side) but the editing UI is crude: three separate full-page-reload forms, a
`<select>` of every song, and ↑/↓ buttons per row. This spec defines a **fast, drag-and-drop
builder** that makes assembling a program quick and direct.

This is primarily a **UX layer** over the existing backend. The data model, tenancy scoping, and
the `add_item` / `remove_item` / `reorder` actions are already in place and are reused, not
rebuilt. Where the backend needs a small extension (e.g. a JSON response instead of a redirect),
that is called out explicitly.

## Decisions (resolved)

- **D-S1 Single-screen builder.** Picking items and ordering them happen on **one screen**
  (the Set show page), not across separate forms and pages. A two-pane layout: a **library
  picker** (left) and the **program list** (right / below on mobile).
- **D-S2 Drag-and-drop is the primary reorder gesture**, with **↑/↓ arrow buttons** retained as
  an accessible, touch-safe fallback (same pattern shipped for the song arrangement builder).
  Keyboard users and screen readers get the arrows; nobody is forced to drag.
- **D-S3 Optimistic, no full-page reloads.** Add / remove / reorder update the program list in
  place (Stimulus + a JSON-returning backend), so building a 12-item set does not flash the page
  twelve times. On a server error the UI reverts and shows a message.
- **D-S4 Reuse the existing item kinds.** An item is a **song**, a **reusable library slide**, or
  a **new inline one-off slide** — exactly the three `add_item` kinds that exist today. No new
  item types in this spec.
- **D-S5 Search, don't scroll.** The library picker is **searchable** (songs by title/author,
  slides by title) rather than a giant `<select>`. It reuses the existing `Song.search` scope.
- **D-S6 Duplicates allowed.** The same song may appear more than once in a set (e.g. an opener
  reprised at the close). Adding an item already in the set appends another occurrence; it does
  not toggle/remove.
- **D-S7 Launch stays where it is.** "Go Live" / launch is an existing action
  (`POST /sets/:id/launch`); the builder surfaces the button but does not change launch behavior.
- **D-S8 Reorder safety preserved.** Reordering continues to go through the existing two-pass
  `reorder` action (park-high-then-assign) so the unique `(set, position)` index is never
  transiently violated. The client sends the full ordered id list; the server is authoritative.
- **D-S9 Server is authoritative on a stale list.** Because a set can change between page load and
  a reorder (another editor, another tab), a reorder whose id set does not match current set
  membership is **rejected**, and the client **re-syncs** from the server rather than forcing its
  stale order. This is the minimum concurrency guard; full real-time collaboration stays out.
- **D-S10 An in-use song/slide cannot be orphaned.** The `set_items` foreign keys are **RESTRICT**
  (no cascade/nullify) and a check constraint requires exactly one reference, so the database
  **already prevents** deleting a song or slide that a set references — a dangling reference cannot
  occur. The real requirement is therefore to **block that deletion gracefully**: deleting a
  library song/slide that is still in any set fails with a clear message instead of a 500. The
  builder additionally carries a cheap defensive `SetItem#missing?` guard (treats a nil reference
  as a removable, non-launchable row) in case a reference is ever orphaned out-of-band.
- **D-S11 Live set edits are allowed but warned.** Editing a set that currently has an active
  `LiveSession` is permitted; the builder shows a **"this set is live"** warning. Launch behavior
  itself is unchanged (D-S7).

## Requirements

### 1. Access and scope
1.1 WHEN a signed-in **editor** opens a Set, THE SYSTEM SHALL render the Set Builder with the
    library picker and the program list.
1.2 WHEN a signed-in **viewer** (non-editor) opens a Set, THE SYSTEM SHALL render the program
    list **read-only** — the library picker SHALL NOT be rendered, and rows SHALL have no drag
    handles and no remove control — consistent with `require_editor` on the mutating actions.
1.3 THE SYSTEM SHALL scope the library picker and every mutation to the signed-in user's church;
    an item from another church SHALL NOT be addable and SHALL be rejected server-side.

### 2. Program list (the set being built)
2.1 THE SYSTEM SHALL display the set's items in `position` order, each showing its title and a
    type indicator (song vs slide).
2.2 THE SYSTEM SHALL show, **for song items only**, the song key when present, to help the
    operator sanity-check the program at a glance. (Slides have no key.)
2.3 WHEN the set has no items, THE SYSTEM SHALL show an empty-state prompt directing the editor to
    add from the library.
2.4 THE SYSTEM SHALL display the item count, updating as items are added/removed.
2.5 THE SYSTEM SHALL prevent deleting a library song or reusable slide that is still referenced by
    any set — the deletion SHALL fail with a clear message rather than a server error — so a set
    item's reference can never dangle. IF a reference is ever orphaned out-of-band, THE SYSTEM
    SHALL render that row as a removable, visibly-flagged placeholder and treat the set as not
    launchable until it is removed (defensive; see D-S10).
2.6 WHEN the set has an active `LiveSession`, THE SYSTEM SHALL display a **"this set is live"**
    warning while still allowing edits (D-S11).

### 3. Adding items
3.1 THE SYSTEM SHALL provide a **searchable song picker**; typing (debounced ~200ms) filters the
    church's songs by title and author via the existing `Song.search` scope.
3.2 THE SYSTEM SHALL provide a **searchable reusable-slide picker**; typing filters by title.
3.3 THE SYSTEM SHALL cap each picker's results (at most **20**) and, when more match, show a
    "refine your search" hint rather than an unbounded list.
3.4 WHEN a picker's query is empty, THE SYSTEM SHALL show a prompt to start typing; WHEN a query
    matches nothing, THE SYSTEM SHALL show a "no matches" message.
3.5 WHEN the editor chooses a song or slide from the picker, THE SYSTEM SHALL append it to the end
    of the program and reflect it in the list **without a full-page reload**.
3.6 THE SYSTEM SHALL provide an **inline one-off slide** form (title, subtype, markdown body) that
    creates a non-reusable slide owned by this set and appends it, as the existing
    `kind=inline_slide` path does.
3.7 WHEN the inline-slide form fails validation (e.g. blank title/body), THE SYSTEM SHALL show the
    field errors on the form and append **nothing** to the program.
3.8 WHEN an add succeeds, THE SYSTEM SHALL return the created item (id, type, title, song key) so
    the client can render the new row without reloading.
3.9 WHEN an add fails (invalid item, cross-church, server error), THE SYSTEM SHALL leave the
    program unchanged and surface an error message.

### 4. Reordering
4.1 THE SYSTEM SHALL let an editor **drag** a program row to a new position; on drop the new order
    SHALL persist via the existing `reorder` action.
4.2 THE SYSTEM SHALL provide **↑ / ↓** controls on each row that move it one step and persist the
    same way (keyboard/touch fallback).
4.3 WHILE a reorder request is in flight, THE SYSTEM SHALL show the new order optimistically; IF
    the request fails, THE SYSTEM SHALL revert to the server's last-known order and show an error.
4.4 THE SYSTEM SHALL send the **complete ordered id list** on every reorder; the server two-pass
    assignment remains the source of truth for `position`.
4.5 WHEN a reorder's id set does not match the set's current membership (an item was added or
    removed since the client loaded), THE SYSTEM SHALL **reject** the reorder and the client SHALL
    re-sync the program list from the server rather than applying its stale order (D-S9).

### 5. Removing items
5.1 THE SYSTEM SHALL provide a remove control per row that deletes that `SetItem` and updates the
    list without a full-page reload.
5.2 WHEN the removed item is an **inline one-off slide**, THE SYSTEM SHALL let the existing
    `dependent: :destroy` / inline-slide ownership rules reap it; a **reusable** library slide
    SHALL only be detached from the set, never deleted from the library.

### 6. Set metadata and launch
6.1 THE SYSTEM SHALL display the set name and service date, with an edit affordance for the name
    and date (reusing the existing `update`).
6.2 THE SYSTEM SHALL surface the **Go Live / Launch** control (existing `launch` route) and, when
    an active `LiveSession` exists for the church, prefer **Resume** over a second launch
    (consistent with the home page's D-H2).

### 7. Feedback and resilience
7.1 THE SYSTEM SHALL apply add / remove / reorder to the DOM **optimistically on the same user
    interaction (no full-page reload, no server round-trip before the visual update)**; the
    persistence request follows asynchronously.
7.2 WHEN any mutation fails, THE SYSTEM SHALL revert the optimistic change and show a non-blocking
    error, leaving the server state authoritative.
7.3 THE SYSTEM SHALL keep **add (all three kinds), remove, and reorder** operable without
    JavaScript via the existing server-rendered forms + redirect responses; the drag-and-drop and
    in-place updates are a progressive enhancement over those, which remain reachable.
7.4 THE JSON `add_item` / `remove_item` / `reorder` responses SHALL re-assert `require_editor` and
    church scoping independently — the enhancement path SHALL NOT rely on the redirect path's
    guards (tenancy risk called out in review).

### 8. Accessibility and mobile
8.1 THE SYSTEM SHALL ensure every drag action has a non-drag equivalent (the ↑/↓ controls) so the
    builder is operable by keyboard and on touch.
8.2 WHEN a row moves via the ↑/↓ controls, THE SYSTEM SHALL keep keyboard focus on the moved row
    and announce its new position via an `aria-live` region.
8.3 THE SYSTEM SHALL use real labelled controls (search inputs, buttons) so the screen is operable
    by assistive technology.
8.4 THE SYSTEM SHALL lay out the two panes responsively — side-by-side on wide screens, stacked
    (picker above program, or a toggle) on narrow screens.

## Out of scope
- New item types beyond song / reusable slide / inline slide (D-S4).
- Changing launch / live-session behavior (D-S7) — the builder only surfaces the existing control.
- Cross-church sharing of sets or a set template/duplication feature.
- Per-item overrides (e.g. a per-set transpose for a song) — a possible later spec.
- Collaborative real-time multi-editor editing of the same set.

## Reused / affected code
- `ServiceSet`, `SetItem` models (unchanged schema).
- `ServiceSetsController#add_item`, `#remove_item`, `#reorder` — extended to answer with JSON (or
  a Turbo Stream) in addition to the current redirect, so the client can update in place (3.5,
  4.x, 5.1). The redirect path stays as the no-JS fallback (7.3).
- `app/views/service_sets/show.html.erb` — rebuilt into the two-pane builder.
- A new Stimulus controller (`set_builder`) for search, optimistic add/remove, and drag-and-drop
  reordering (arrows + drag), mirroring the song arrangement builder's interaction model.
- `Song.search` scope (3.1).
