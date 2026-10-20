# Slide Tags & Slide Groups — Requirements

Two changes to text slides:

1. **Tags replace the fixed `subtype`.** Today a slide has one `subtype` from a closed enum
   (`statement`, `scripture`, …) that drives both organization and projector styling. Replace it
   with **free-form tags**: zero or more labels an author types (creating them on the spot), used
   to organize and **search** slides. The enum goes away.
2. **A slide can be a group of pages.** When a slide's text is too long for one projected screen,
   it can hold **multiple ordered pages** that are one logical slide in the library and the set,
   but project one page at a time — the operator's **Next** steps through the pages.

Resolved with the user: tags fully replace subtype (styling becomes uniform — decision D-T1); group
pages advance individually during a live service (D-T2).

## Decisions (resolved)

- **D-T1 Tags replace subtype entirely; no per-type styling.** The `subtype` column and its enum
  check constraint are removed. Slides render with ONE neutral style on projector/musician
  (the `slide-<subtype>` CSS variants are retired). Tags are organizational + searchable only;
  they do not change appearance.
- **D-T2 A slide group projects one page at a time; Next advances through pages.** A grouped slide
  contributes N stops to the live walk (one per page), exactly as a song contributes one stop per
  section — reusing the existing `LivePosition.section_count_for` hook (returns the page count for
  a slide instead of always 1). In the library and the set it is ONE item.
- **D-T3 Minimum viable data model: pages as an ordered array on the slide.** A slide stores its
  pages as an **ordered list of markdown bodies** (JSONB array), not as child rows. A single-page
  slide is just a one-element array — so every existing slide is trivially a one-page group and no
  "is it a group?" flag is needed. This avoids a child table and keeps `SetItem` referencing one
  `text_slide` unchanged.
- **D-T4 Tags are per-church, free-form, normalized.** A tag is a short text label scoped to the
  church; typing an existing label reuses it, a new one is created on save. Stored as a
  string array on the slide (JSONB), lower-cased and de-duplicated. No separate tags table in v1
  (a tag is just a string); the church's existing tag vocabulary is derived by DISTINCT over
  slides for autocomplete.
- **D-T5 Backfill, don't break.** Existing slides' `subtype` value becomes a **tag** on migration
  (so "scripture" slides stay findable by the tag "scripture"), and their single `body_markdown`
  becomes a one-element `pages` array. No slide loses data.
- **D-T6 The WYSIWYG editor and live preview are preserved** (from the just-shipped slide editor):
  each page is edited with the contenteditable toolbar, markdown hidden; the preview shows the
  current page.

## Requirements

### 1. Tags
1.1 THE SYSTEM SHALL let an editor attach zero or more free-form **tags** to a slide, adding a new
    tag by typing it (created on the spot) and removing a tag from the slide.
1.2 THE SYSTEM SHALL normalize tags (trim, lower-case, de-duplicate) and scope them to the slide's
    church.
1.3 THE SYSTEM SHALL offer **autocomplete** from the church's existing tags while the editor types,
    without preventing a brand-new tag.
1.4 THE SYSTEM SHALL remove the `subtype` field from the slide form and model; a slide no longer
    has a type.
1.5 WHEN searching slides, THE SYSTEM SHALL match the query against **title and tags** (and body),
    so a slide is findable by any of its tags.
1.6 THE SYSTEM SHALL let a user filter the slide library to a specific tag.

### 2. Slide groups (pages)
2.1 THE SYSTEM SHALL let a slide hold **one or more ordered pages**, each with its own body; a
    slide with one page is the common case and needs no special handling.
2.2 THE SYSTEM SHALL let an editor **add a page**, **remove a page**, **reorder pages**, and edit
    each page with the WYSIWYG body editor.
2.3 THE SYSTEM SHALL show which page is being edited and how many pages the slide has.
2.4 WHEN a slide has multiple pages, THE SYSTEM SHALL project **one page per screen**, and the live
    operator's **Next / Back** SHALL step through the pages in order before moving to the next set
    item (reusing the section-walk machinery).
2.5 IN the library and in a set, a multi-page slide SHALL appear as **one item**, with an
    indication of its page count.
2.6 THE SYSTEM SHALL render the musician/projector view of the **current page** of a grouped slide.

### 3. Rendering & styling
3.1 THE SYSTEM SHALL render every slide with one neutral, readable style (no per-subtype CSS); the
    retired `slide-<subtype>` classes and `data-subtype` attributes SHALL be removed from the slide
    partials.
3.2 THE SYSTEM SHALL keep the server-side markdown rendering (commonmarker, HTML-escaped) for each
    page's body — the projector pipeline is otherwise unchanged.

### 4. Migration & compatibility
4.1 THE SYSTEM SHALL migrate every existing slide: its `subtype` becomes a tag; its
    `body_markdown` becomes the first (and only) page. No data is lost.
4.2 THE SYSTEM SHALL drop the `subtype` column and its check constraint after backfill.
4.3 THE SYSTEM SHALL keep `SetItem` referencing a single `text_slide` unchanged (a group is still
    one slide row), so set membership, the set builder, and launch are unaffected except that a
    grouped slide now contributes multiple live stops (D-T2).
4.4 THE SYSTEM SHALL keep inline one-off slides (set-owned, `reusable: false`) working with pages
    and tags like any other slide.

### 5. Editor UX
5.1 THE SYSTEM SHALL present the slide editor as: Title, a **tags input** (chips + autocomplete),
    and a **pages editor** (the WYSIWYG body per page, with add/remove/reorder page controls), plus
    the existing live preview of the current page.
5.2 THE SYSTEM SHALL keep the Advanced raw-markdown escape hatch per page.

## Out of scope
- A normalized tags table / tag management screen (tags are strings in v1, D-T4).
- Per-tag or per-slide custom styling/themes (D-T1 makes styling uniform).
- Re-ordering set items — unchanged; this spec only changes what one slide item contains.
- Rich media on slides (images/video).
- Collaborative editing.

## Reused / affected code
- `TextSlide` model: drop `subtype`; add `tags` (JSONB string array) and `pages` (JSONB array of
  `{body_markdown}`); `rendered_html` becomes per-page; `search` matches tags.
- Migration: add columns, backfill (subtype→tag, body→pages[0]), drop `subtype` + constraint.
- `TextSlidesController`: tags/pages params; `library`/index search + tag filter; `preview` per page.
- `Corobook::LivePosition#section_count_for`: return a slide's page count (was always 1).
- `Corobook::LiveFrame`: render the current page of a slide by `current_section_index`.
- Slide partials (`_projector_slide`, `_musician_slide`): drop subtype class/attr, render current
  page; show-page and index.
- `slide_editor` Stimulus controller: multi-page + tags-chips, preserving the WYSIWYG body.
- Set builder inline-slide add (one page) stays compatible.
