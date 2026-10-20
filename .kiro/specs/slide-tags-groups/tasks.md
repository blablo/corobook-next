
Implements `slide-tags-groups/{requirements,design}.md`. Ordered model/migration-first (headless-
tested), then live-advance integration, then the editor UX (system-tested). The `subtype` enum is
removed; `tags` + `pages` (JSONB) replace it, backfilled losslessly. `SetItem` is unchanged.

Branch off `develop`; implement → test → green → commit per task. One branch + one PR to `develop`.

## 1. Data model & migration

- [ ] 1.1 Migration: add `tags` jsonb (default []), `pages` jsonb (default []); backfill every
  slide (`tags = [subtype]`, `pages = [{body_markdown: body_markdown}]`); drop `subtype` column +
  its check constraint; GIN index on `tags`. Test: run migrate; a pre-existing slide has
  `tags == ["scripture"]` and `pages == [{"body_markdown" => <old body>}]`; `subtype` gone.
  _Requirements: 4.1, 4.2_ _Design: §1_

- [ ] 1.2 `TextSlide` model: `normalize_tags_and_pages` (before_validation: trim/lower/unique tags;
  pages → array of `{body_markdown}`, always ≥1); `page_count`, `page_markdown(i)`,
  `rendered_html(i=0)`; `tagged(tag)` scope; `search` also matches `tags::text`; remove `subtype`
  enum + `subtype_class`. Unit tests: normalize cases; `tagged`; `search` by tag; `rendered_html`
  per page; empty pages → one blank page.
  _Requirements: 1.1, 1.2, 1.5, 2.1, 3.2_ _Design: §2_

## 2. Live advance integration

- [ ] 2.1 `LivePosition#section_count_for` → `text_slide.page_count` for slides (was 1);
  `LiveFrame` renders the current page via `current_section_index`. Tests: a 2-page slide yields 2
  stops; `next_stop`/`prev_stop` walk page 0 → 1 → next item; the frame renders the correct page;
  a 1-page slide behaves exactly as before.
  _Requirements: 2.4, 2.6_ _Design: §3_

## 3. Controller, search, rendering

- [ ] 3.1 `TextSlidesController`: `slide_params` permits `tags: []` and `pages: [:body_markdown]`;
  `create`/`update` build pages+tags; index gains a `tag` filter (`tagged`) and exposes
  `@church_tags`; `preview` renders one page's markdown (drop `subtype_class`). Request tests: tag
  filter narrows the index; search finds a slide by a tag; create with tags+pages persists;
  inline-slide add path (set builder) still creates a one-page, no-tag slide.
  _Requirements: 1.3, 1.5, 1.6, 4.3, 4.4_ _Design: §4_

- [ ] 3.2 Slide partials (`_projector_slide`, `_musician_slide`) + show: drop `subtype_class` /
  `data-subtype`; render the current page; neutral style. Keep server markdown. Tests: projector/
  musician render page content with no subtype class; multi-page show renders page 0 by default.
  _Requirements: 3.1, 3.2, 2.6_ _Design: §5_

## 4. Editor UX (WYSIWYG preserved)

- [ ] 4.1 Tags input: chip list + text field with `<datalist>` autocomplete from `@church_tags`;
  Enter/comma adds, ✕ removes; serialize to hidden `tags[]`; client normalize mirrors server.
  _Requirements: 1.1, 1.3, 5.1_ _Design: §6_

- [ ] 4.2 Pages editor: page selector (Page i of N) with add/remove/reorder; the existing WYSIWYG
  contenteditable + Advanced toggle + live preview bind to the ACTIVE page; serialize all pages to
  hidden `pages[][body_markdown]`. Preserve the hidden-markdown round-trip per page.
  _Requirements: 2.2, 2.3, 5.1, 5.2_ _Design: §6_

- [ ] 4.3 Index: tag-filter chip row (`?tag=`), per-row tags + "N pages" badge when `page_count>1`.
  _Requirements: 1.6, 2.5_ _Design: §5_

## 5. Finish

- [ ] 5.1 Update the slide-editor system test (no subtype; create with tags + 2 pages via WYSIWYG;
  search by tag; "2 pages" badge). Rebuild Tailwind; full suite + system + Rubocop + Brakeman green;
  existing set/live tests still green. Screenshot the editor + index; open the PR to `develop`.
  _Requirements: all_ _Design: §7_

## Notes
- JSONB arrays, no child tables, no new gem. `body_markdown` column is left in place but unused
  after backfill (pages[0] is the truth) to avoid a lossy drop.
- Keep the html redirect/paths; the shipped WYSIWYG + preview from the slide-editor PR is the base
  this extends — do not regress it.
