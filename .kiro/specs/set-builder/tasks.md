
Implements `set-builder/{requirements,design}.md`. Ordered backend-first: JSON contract + search +
guards (headless/request-tested), then the two-pane view and Stimulus controller
(system-tested/screenshot-verified), then the edge cases the review surfaced. The `ServiceSet` /
`SetItem` schema and the html redirect paths are unchanged — every task must keep the existing
set/live-session tests green.

Branch off `develop`; implement → test → green → commit per task. Per the repo workflow this ships
as one branch + one PR targeting `develop`.

## 1. Backend: JSON contract + presenter (no UI yet)

- [ ] 1.1 **Missing-reference presenter.** Add `SetItem#missing?` (`item.nil?`) and
  `#resolved_title` (`item&.title`). Unit tests: a set item whose song/slide was destroyed reports
  `missing? == true` and a nil title; a normal item reports the real title.
  _Requirements: 2.5_ _Design: §2_

- [ ] 1.2 **`item_json` helper + `add_item` JSON branch.** Add a private `item_json(set_item)`
  returning `{id, kind, title, key, missing}` (key only for songs). Wrap `add_item` in
  `respond_to`: `json` → `201` with `item_json` on success, `422` `{error: [...]}` on
  `RecordInvalid`; `html` → the existing redirect (unchanged). Request tests: JSON add of a song
  returns 201 + shape; invalid inline slide returns 422 and creates no item; cross-church song id
  is rejected; html POST still redirects.
  _Requirements: 3.5, 3.7, 3.8, 3.9, 1.3, 7.3, 7.4_ _Design: §1.1, §1.4_

- [ ] 1.3 **`reorder` stale-list guard + JSON branch.** Before the two-pass assignment, compare the
  submitted id set to `set_items.pluck(:id)`; on mismatch return `409` `{error:"stale", items:
  [...]}` (json) / redirect+alert (html). On match, run the existing two-pass reorder and return
  `204` (json) / redirect (html). Request tests: valid reorder persists order and returns 204;
  a reorder whose ids differ from membership returns 409 with the current items and does NOT
  change positions; html path still redirects.
  _Requirements: 4.4, 4.5, 7.3_ _Design: §1.2_

- [ ] 1.4 **`remove_item` JSON branch.** `respond_to`: `json` → `204`; `html` → redirect. Keep the
  inline-slide `dependent: :destroy` reap and reusable-slide detach-only behavior. Request tests:
  JSON remove returns 204 and deletes the SetItem; removing an inline-slide item reaps the slide;
  removing a reusable-slide item leaves the library slide intact.
  _Requirements: 5.1, 5.2_ _Design: §1.1_

- [ ] 1.5 **`library` search endpoint + route.** Add `get "library"` member route and
  `ServiceSetsController#library` (church-scoped, `kind=song|slide`, `Song.search` / title ILIKE,
  `.limit(20)`). Returns JSON rows (`{id,kind,title,key?}`). Request tests: song search filters by
  title/author and caps at 20; slide search returns only reusable slides; results are
  church-scoped; blank query returns the first 20 by title.
  _Requirements: 3.1, 3.2, 3.3, 1.3_ _Design: §1.3_

## 2. View: two-pane builder (progressive-enhancement base)

- [ ] 2.1 **Rebuild `service_sets/show.html.erb` server-rendered first.** Two-pane grid (program
  left, picker right; stacks on mobile). Program `ol` with `data-role=set-item`, drag handle, #,
  title, song key, ↑/↓ (`button_to` reorder — existing), ✕ (remove). Missing items render a
  flagged, removable placeholder; launch control disabled while any item is missing. Picker tabs
  hold the existing three forms (song select, reusable-slide select, inline-slide form) — still
  posting normally. Header: name + service_date, Go Live/Resume, "this set is live" warning when an
  active `LiveSession` exists. Viewer (non-editor): program only, no handles/✕/picker. This step
  is the **JS-off fallback** and must be fully usable on its own. System tests: editor sees picker
  + program; viewer read-only; missing-item placeholder + disabled launch; live warning shows.
  _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.4, 3.6, 6.1, 6.2, 7.3, 8.3, 8.4_
  _Design: §3_

## 3. Stimulus `set_builder` controller (the enhancement)

- [ ] 3.1 **Controller scaffold + search.** New `set_builder_controller.js`; wire
  `data-controller` + values (`reorderUrl`, `addUrl`, `libraryUrl`, `canEdit`) + targets. Debounced
  (~200ms) search → `GET libraryUrl` → render ≤20 results; empty-query prompt, no-results message,
  "refine" hint when 20 returned. System test: typing filters results; no-results shows the message.
  _Requirements: 3.1, 3.2, 3.3, 3.4_ _Design: §4_

- [ ] 3.2 **Optimistic add.** Click a result (or submit inline-slide form) → append row optimistically
  → `POST addUrl` (JSON) → swap in real id on 201; 422 shows inline-slide field errors and removes
  the optimistic row; other errors revert + flash. Intercept the legacy forms when JS is on. System
  tests: add song/slide/inline appears without reload; blank inline title → error, nothing added.
  _Requirements: 3.5, 3.6, 3.7, 3.8, 3.9, 7.1, 7.2_ _Design: §4_

- [ ] 3.3 **Reorder: arrows + drag.** Direct listeners on rows (dynamic-node binding lesson): ↑/↓
  move one step, keep focus on the moved row, announce via `aria-live`; native DnD
  dragstart/dragover/drop reorders the DOM. Both `PATCH reorderUrl` with the full ordered id list,
  optimistically. System tests: ↑/↓ persists across reload; simulated drop persists; focus +
  announce on arrow move.
  _Requirements: 4.1, 4.2, 4.3, 4.4, 8.1, 8.2_ _Design: §4_

- [ ] 3.4 **Reconcile + remove.** Optimistic remove → `DELETE` → revert on error. Any mutating fetch
  returning **409** replaces the program list from the response `items` and flashes "the set
  changed — reloaded". Launch stays disabled client-side while any row is `data-missing`. CSRF
  header on every fetch. System test: remove updates in place; 409 path re-syncs the list.
  _Requirements: 4.5, 5.1, 7.2_ _Design: §1.2, §4_

## 4. Hardening & finish

- [ ] 4.1 Rebuild Tailwind CSS (new classes compile); confirm dark-mode-safe via DaisyUI theme
  variables only. Full suite + system + Rubocop + Brakeman green.
  _Requirements: 8.3, 8.4_ _Design: §5_

- [ ] 4.2 Screenshot-verify the two-pane builder (desktop + a narrow viewport) and attach to the PR.
  Open the PR to `develop` with the requirements/design/tasks traceability.
  _Design: §5_

## Notes
- No schema change and no new gem (native DnD). The html redirect paths are untouched, so existing
  `service_sets` / `live_sessions` tests must stay green throughout — treat a red one as a
  regression, not an expected churn.
- Commit per task with a conventional message; keep the branch rebased on `develop`.
