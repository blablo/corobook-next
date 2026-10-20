# Slide Tags & Slide Groups — Design

Implements `slide-tags-groups/requirements.md`. Replaces the `subtype` enum with free-form `tags`
and lets a slide hold ordered `pages`, both stored as JSONB on `text_slides` (no child tables,
no new gem). The live-advance machinery already walks "sections" per set item; a slide's page
count plugs into that hook, so grouped slides project one page per Next with no new state.

## 1. Schema & migration

```ruby
# db/migrate/XXXX_slides_tags_and_pages.rb
add_column :text_slides, :tags,  :jsonb, null: false, default: []
add_column :text_slides, :pages, :jsonb, null: false, default: []

# Backfill (D-T5): subtype -> a tag; body_markdown -> pages[0].
TextSlide.reset_column_information
execute <<~SQL
  UPDATE text_slides
     SET tags  = to_jsonb(ARRAY[subtype]),
         pages = jsonb_build_array(jsonb_build_object('body_markdown', COALESCE(body_markdown, '')))
SQL

remove_column :text_slides, :subtype   # drops the column AND its check constraint
# body_markdown is kept as a column but no longer the source of truth (pages[0] is); left in place
# to avoid a lossy drop — the model stops reading it.
add_index :text_slides, :tags,  using: :gin
```

GIN index on `tags` makes tag containment/search fast. `pages` needs no index (read with the row).

## 2. Model (`TextSlide`)

```ruby
# tags: ["scripture", "advent"]  — lower-cased, unique, church-scoped by the row.
# pages: [{ "body_markdown" => "..." }, ...]  — ordered; >= 1 element after normalize.

before_validation :normalize_tags_and_pages

def normalize_tags_and_pages
  self.tags  = Array(tags).map { |t| t.to_s.strip.downcase }.reject(&:blank?).uniq
  self.pages = Array(pages).map { |p| { "body_markdown" => p["body_markdown"].to_s } }
  self.pages = [ { "body_markdown" => "" } ] if pages.empty?   # always >= 1 page
end

def page_count = pages.length
def page_markdown(i) = pages[i.clamp(0, page_count - 1)]["body_markdown"].to_s
def rendered_html(page_index = 0)
  Commonmarker.to_html(page_markdown(page_index).encode("UTF-8"))
end

# Search now also matches tags. tags is JSONB; use a text cast for ILIKE OR a GIN containment.
scope :search, ->(q) {
  next all if q.blank?
  pattern = "%#{sanitize_sql_like(q.to_s.strip)}%"
  where("title ILIKE :p OR body_markdown ILIKE :p OR tags::text ILIKE :p", p: pattern)
}
scope :tagged, ->(tag) { where("tags @> ?", [ tag.to_s.downcase ].to_json) }

# subtype_class is removed.
```

The church's tag vocabulary for autocomplete:
```ruby
# TextSlidesController
def church_tags = church_scope(:text_slides).pluck(:tags).flatten.uniq.sort
```
(Small libraries → fine as a pluck; if it grows, a `SELECT DISTINCT jsonb_array_elements_text(tags)`
replaces it. Out of scope to optimize now.)

## 3. Live advance (the group hook)

```ruby
# Corobook::LivePosition#section_count_for
item.item_type == "song" ? song_section_count(item.song) : item.text_slide.page_count
```
`LiveFrame` renders the current page:
```ruby
# when text_slide?, the frame's section_index selects the page
slide.rendered_html(session.current_section_index)
```
No new columns on `live_sessions` — `current_section_index` already means "which section of the
current item", and a page is a section. A one-page slide → count 1 → identical to today.

## 4. Controller & routes

```ruby
# params: title, tags (array), pages (array of { body_markdown })
def slide_params
  params.require(:text_slide).permit(:title, tags: [], pages: [ :body_markdown ])
end

# index: optional tag filter
@text_slides = church_scope(:text_slides).where(reusable: true)
@text_slides = @text_slides.tagged(params[:tag]) if params[:tag].present?
@text_slides = @text_slides.search(@query).order(:title)
@church_tags = church_tags   # for the filter UI + editor autocomplete

# preview endpoint renders ONE page's markdown (unchanged shape minus subtype_class)
def preview
  render json: { html: Commonmarker.to_html(params[:body_markdown].to_s.encode("UTF-8")) }
end
```
`library` (set-builder picker) is unaffected (title search). The inline-slide add path builds a
one-page slide (`pages: [{ body_markdown: ... }]`, `tags: []`).

## 5. Views

- **Editor** (`_form`): Title; a **tags field** (chip list + text input with a `<datalist>` of
  `@church_tags` for autocomplete); a **pages editor** — a page selector (Page 1 of N, add /
  remove / reorder) above the existing WYSIWYG contenteditable + Advanced toggle + live preview,
  all bound to the *current* page. Hidden inputs serialize `tags[]` and `pages[][body_markdown]`.
- **Index**: a tag filter row (chips linking to `?tag=`), each slide row shows its tags + a
  "N pages" badge when `page_count > 1`.
- **Show / projector / musician partials**: drop `subtype_class` + `data-subtype`; render the
  current page (default page 0 on the standalone show). Neutral style only.

## 6. Stimulus `slide_editor` controller (extended)

Keeps the WYSIWYG body + preview from the shipped version; adds:
- **Pages model**: an in-memory array of page markdown; the contenteditable edits the active page;
  `addPage` / `removePage` / `prevPage` / `nextPage` / `reorder`; serialize all pages into hidden
  `pages[][body_markdown]` inputs on change.
- **Tags**: typing + Enter/comma adds a chip; ✕ removes; chips serialize into hidden `tags[]`
  inputs; `<datalist>` gives autocomplete. Normalization mirrors the server (trim/lower/unique).
- Preview renders the active page via the existing `preview` endpoint.

## 7. Testing

Model: tag normalize (trim/lower/unique), pages normalize (≥1), `tagged` scope, `search` matches a
tag, `rendered_html(i)` per page, `page_count`.
Migration: a pre-existing slide gains `tags == [old subtype]` and `pages == [{body_markdown: old
body}]`; `subtype` column gone.
LivePosition/LiveFrame: a 2-page slide yields 2 stops; Next walks page 0 → page 1 → next item;
the frame renders the right page.
System: create a slide with 2 tags + 2 pages via the editor (WYSIWYG, no markdown shown); search
finds it by a tag; filter by tag; the library shows "2 pages". Existing slide-editor test updated
(no subtype; tags instead).
Controller: index tag filter; search by tag; inline-slide add still works (one page, no tags).
Rubocop + Brakeman clean; existing set/live tests stay green (SetItem→text_slide unchanged).

## 8. Out of scope (per requirements)
Normalized tags table, tag management screen, per-tag styling, media, collaborative editing.
