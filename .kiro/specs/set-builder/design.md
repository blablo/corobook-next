# Set Builder — Design

Implements `set-builder/requirements.md`. A single-screen, two-pane builder (library picker +
program list) layered over the **existing** `ServiceSet` / `SetItem` backend. The model schema
and the `add_item` / `remove_item` / `reorder` actions already exist; this design **extends** them
to answer JSON for the enhancement path while keeping their redirect responses as the no-JS
fallback (Req 7.3), and adds a search endpoint and one Stimulus controller.

Stack: Rails + Hotwire (Turbo + Stimulus), importmap/no-build, Tailwind v4 + DaisyUI v5 (admin
light theme, per the home design). Drag-and-drop uses the native HTML Drag and Drop API with an
↑/↓ fallback — the same zero-dependency pattern shipped in the song arrangement builder.

## 1. Routing & controller

Existing member routes are reused; one new collection-ish member route for the picker search:

```ruby
resources :service_sets, path: "sets", as: :service_sets do
  member do
    post   "items",            to: "service_sets#add_item",    as: :add_item
    patch  "reorder"
    delete "items/:item_id",   to: "service_sets#remove_item", as: :remove_item
    post   "launch",           to: "live_sessions#create",     as: :launch
    get    "library",          to: "service_sets#library",     as: :library   # NEW (picker search)
  end
end
```

### 1.1 `respond_to` on the three mutating actions
Each mutating action keeps its current redirect for `html` and gains a `json` branch (Req 3.8,
4.x, 5.1, 7.3). Controller-level `require_editor` already guards all of them (Req 7.4 — the JSON
path inherits the same `before_action`, it does not bypass it).

```ruby
def add_item
  item = build_item_from_params   # song | text_slide | inline_slide, church-scoped find
  position = (@service_set.set_items.maximum(:position) || -1) + 1
  @item = @service_set.set_items.create!(position:, **item)
  respond_to do |f|
    f.json { render json: item_json(@item), status: :created }
    f.html { redirect_to @service_set }
  end
rescue ActiveRecord::RecordInvalid => e
  respond_to do |f|
    f.json { render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity }
    f.html { redirect_to @service_set, alert: e.record.errors.full_messages.to_sentence }
  end
end
```

### 1.2 Stale-list guard on `reorder` (Req 4.5 / D-S9)
Before the existing two-pass assignment, compare the submitted id **set** to current membership.
A mismatch means the client's list is stale → reject with the current order so the client
re-syncs; never apply a partial order.

```ruby
def reorder
  ids = Array(params[:ordered_ids]).map(&:to_i)
  current = @service_set.set_items.pluck(:id)
  if ids.sort != current.sort
    return respond_to do |f|
      f.json { render json: { error: "stale", items: ordered_items_json }, status: :conflict }
      f.html { redirect_to @service_set, alert: "The set changed — reloaded." }
    end
  end
  SetItem.transaction do          # existing two-pass park-high-then-assign (D-S8)
    offset = (@service_set.set_items.maximum(:position) || 0) + 1000
    ids.each_with_index { |id, i| @service_set.set_items.where(id:).update_all(position: offset + i) }
    ids.each_with_index { |id, i| @service_set.set_items.where(id:).update_all(position: i) }
  end
  respond_to { |f| f.json { head :no_content }; f.html { redirect_to @service_set } }
end
```

`409 Conflict` is the agreed "your list is stale, here is the truth" signal; the client replaces
its rows with `items` and shows a notice.

### 1.3 `library` (picker search, Req 3.1–3.4)
Read-only, church-scoped, capped at 20 (Req 3.3). One endpoint, `kind=song|slide`:

```ruby
def library
  case params[:kind]
  when "slide"
    rows = church_scope(:text_slides).where(reusable: true)
             .where("title ILIKE ?", "%#{TextSlide.sanitize_sql_like(params[:q].to_s)}%")
             .order(:title).limit(20)
    render json: rows.map { |s| { id: s.id, kind: "text_slide", title: s.title } }
  else
    rows = church_scope(:songs).search(params[:q]).order(:title).limit(20)
    render json: rows.map { |s| { id: s.id, kind: "song", title: s.title, key: s.song_key } }
  end
end
```

(Capping at 20 and returning fewer than the real match count is how the client knows to show the
"refine your search" hint — it requests 21, shows 20, flags "more".)

### 1.4 JSON shapes (the client contract)

```jsonc
// item_json (add_item 201, and each element of reorder-conflict items)
{ "id": 42, "kind": "song", "title": "Cuán Grande es Dios", "key": "G", "missing": false }
// kind: "song" | "text_slide"; key present only for songs; missing=true when the
// referenced song/slide no longer exists (Req 2.5 / D-S10)
```

## 2. Missing-reference handling (Req 2.5 / D-S10)

`SetItem#item` already returns `song || text_slide`; when the reference was deleted it returns
`nil`. A small presenter method centralizes the "missing" state so both the server render and the
JSON agree:

```ruby
# SetItem
def resolved_title = item&.title
def missing? = item.nil?
```

The program row renders a flagged placeholder when `missing?`, is removable, and the launch
control is disabled while any item is missing (not launchable). No schema change.

## 3. View — `service_sets/show.html.erb` (two-pane)

```
┌ header: set name + service_date (inline-editable), Go Live/Resume, "live" warning ┐
├ grid lg:grid-cols-[1fr_minmax(0,22rem)] (program left, picker right; stacks on mobile)
│  ┌ PROGRAM (data-role=set-items) ─────────────┐  ┌ LIBRARY PICKER (editors only) ─┐
│  │ ol, each <li data-item-id data-role=set-item│  │ tabs: Songs | Slides | New slide│
│  │   drag handle ⠿ | # | title | key | ↑ ↓ ✕   │  │ search input (debounced)         │
│  │ empty-state when none                        │  │ results (≤20) + "refine" hint    │
│  └──────────────────────────────────────────── ┘  │ inline-slide form (3rd tab)      │
└───────────────────────────────────────────────────┴─────────────────────────────────┘
```

- Whole view wrapped in `data-controller="set-builder"` with
  `data-set-builder-{reorder,add,library}-url-value` and `data-set-builder-can-edit-value`.
- The existing three server-rendered forms are retained but visually folded into the picker tabs;
  they POST normally (the Stimulus `submit` handler intercepts when JS is on). This is the Req 7.3
  fallback — with JS off, the forms and ↑/↓ `button_to`s still work exactly as today.
- Viewer (non-editor): render only the program `ol`, no handles / ✕ / picker (Req 1.2).
- An `aria-live="polite"` region holds move announcements (Req 8.2).

## 4. Stimulus `set_builder_controller.js`

Targets: `program` (the `<ol>`), `row` (each `<li>`), `query` (search input), `results`,
`announce` (aria-live), `launch`. Values: `reorderUrl`, `addUrl`, `libraryUrl`, `canEdit`.

Responsibilities:
- **Search** (`query` input): debounce ~200ms → `GET libraryUrl?kind&q` → render ≤20 result rows;
  empty query shows the prompt, empty result shows "no matches", a full 20 shows the "refine"
  hint (Req 3.1–3.4).
- **Add**: click a result → optimistic append of a row → `POST addUrl` → on 201 swap in the real
  id from `item_json`; on error remove the optimistic row and flash (Req 3.5–3.9, 7.1–7.2).
  Inline-slide form posts JSON; 422 renders field errors and appends nothing (Req 3.7).
- **Reorder — drag**: native DnD on `row` (`dragstart/dragover/drop`), reorder DOM optimistically,
  then `PATCH reorderUrl` with the full ordered id list. (Direct listeners on the rows — Stimulus
  action binding on dynamically-inserted nodes races, a lesson already learned in the song
  editor.)
- **Reorder — arrows**: ↑/↓ move one step, keep focus on the moved row, announce new position via
  `announce` (Req 4.2, 8.2).
- **Reconcile**: any mutating fetch that returns **409** replaces the program list from the
  response's `items` and flashes "the set changed — reloaded" (Req 4.5 / D-S9). Any 5xx/4xx
  reverts the optimistic change (Req 7.2).
- **CSRF**: read `content="csrf-token"` meta and send `X-CSRF-Token` on every fetch.

Reorder payload: `PATCH reorderUrl { ordered_ids: [ids...] }`. Launch disabled client-side while
any `row` has `data-missing="true"` (Req 2.5).

## 5. Testing

System (Capybara, the primary coverage — matches the song-editor/arrangement tests):
- Add a song via search → appears in program; add a reusable slide; add an inline slide.
- Inline-slide blank title → field error, nothing appended (Req 3.7).
- Reorder with ↑/↓ → order persists across reload; drag reorder persists (drag simulated via the
  controller's drop handler, as the arrangement test does).
- Remove a song (detaches) and an inline slide (reaped) (Req 5.1–5.2).
- Viewer (non-editor) sees read-only program, no picker/handles (Req 1.2).
- Stale reorder → 409 path: simulate by deleting an item server-side between load and reorder,
  assert the list re-syncs (Req 4.5).
- Missing reference: delete a referenced song, reload → placeholder row, launch disabled (Req 2.5).

Controller/integration:
- `add_item` / `reorder` / `remove_item` JSON branches return the documented shapes and status
  codes; `reorder` returns 409 on an id-set mismatch; cross-church add is rejected (Req 1.3, 7.4).
- `library` is church-scoped, caps at 20, filters by query.

Rubocop + Brakeman clean; existing set/live-session tests stay green (the html redirect paths are
unchanged).

## 6. Out of scope (unchanged from requirements)
No new item types, no launch-behavior change, no templates/duplication, no per-item transpose, no
real-time multi-editor collaboration (only the stale-list guard of §1.2).
