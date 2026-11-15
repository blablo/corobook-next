---
name: corobook-import
description: Import songs and text slides from a PDF (or pasted text) into corobook-next through its token-authenticated JSON API. Use when the user hands over a PDF/songbook/slide deck text and wants the songs and slides created in Corobook.
triggers: import pdf into corobook, create songs from pdf, create slides from pdf, corobook import, add these songs to corobook, extract songs from pdf
---

# Corobook import (PDF -> songs + text slides)

Paths below are relative to the corobook-next repo root. The API is documented in `docs/import_api.md`; the PDF converter is `.kiro/skills/corobook-import/pdf2md.rb` (next to this file). The dev app runs in the `corobook-next-web-1` container.

## Setup (once)
- Base URL: `https://next.corobook.com` (church is set by the token's user, not the host). Dev: `http://127.0.0.1:3000`.
- Token (prod): the user runs `bin/rails corobook:issue_api_token EMAIL=<email> NAME="pdf import"` on the server and gives you the `cbk_...` value. Never store it in memory/lessons or echo it back.
- Token (dev): you may mint a throwaway one yourself with `docker exec corobook-next-web-1 bin/rails corobook:issue_api_token EMAIL=<editor email> NAME="<job name>"`, keep it in a `chmod 600` file under `$KIROCREW_SCRATCH`, and when done delete both the file and the token (`bin/rails runner 'ApiToken.where(name: "<job name>").destroy_all'`).

## Workflow
1. Extract the text page by page inside the container (the host may have no poppler): `docker cp` the PDF to `corobook-next-web-1:/tmp/`, then `pdftotext -f N -l N -layout`. List every page's first line first to map pages to items. If it is scanned/unreadable, say so and ask for a text version. Remove the PDF from the container when done.
2. Classify each item: **song** (lyrics, optionally with chords) or **text slide** (announcement, scripture, statement, sermon point, etc.). If unclear, ask.
3. Build the payloads (formats below). Do NOT invent authors, keys, CCLI numbers or copyright; leave blank unless in the PDF.
4. Check duplicates: `GET /api/v1/songs?q=<title>` / `/api/v1/text_slides?q=<title>`. A `409 duplicate` on POST means it exists; skip and report, never overwrite.
5. **Dry run first** for the whole batch (`"dry_run": true`); stop if any item fails validation. Then read what the dry run returns, not just its status:
   - Song: `warnings` must be empty (an empty section = a blank line in `chordpro_source`; an arrangement label that names no section). `sections` must list the labels and lines you meant.
   - Slide: `pages_html` is each page exactly as the projector renders it. Check the italic / bold italic runs, line breaks and `<sub class="slide-small">` for small lines.
   Fix the payload and dry-run again until both are clean.
6. **Confirm each item with the user, one at a time** (default; the user may say "create all"). The confirmation must show the FULL content, not a summary:
   - Song: title, author, key, copyright line, CCLI number, copyright status, and every section with its label, its PDF page number(s) and all its lyric lines (chords if any).
   - Text slide: title, tags, font size, line spacing, alignment and colours, and every page's full text, numbered ("Page 1 of N") with its PDF page. Mark small lines, e.g. "(small) (Psalm 25:6-8)".
   - Name every inference below the content: a title or reference not printed in the PDF, a guessed section label, a repaired word, a page the PDF cuts mid-sentence, text you dropped.
   Put that in the message body (or the question text), then ask: Create it / Skip it / Stop here. Never ask "create song X?" with only a title.
7. POST for real only the confirmed items, one request per item; report created ids/urls, skipped duplicates and any `422` messages.

## Fixing something already imported
Never edit the DB directly (`rails runner`) to fix imported content; use the API so the church scoping and validations apply.
1. `GET /api/v1/songs/:id` or `/api/v1/text_slides/:id` to read the stored content.
2. `PATCH` the same path with ONLY the fields to change and `"dry_run": true`; show the user `would_change` plus the new content in full.
3. After the user confirms, PATCH again without `dry_run`. Sending `pages` replaces every page, so always send the full list.

## Song payload
Section structure from a slide deck PDF: **one PDF slide = one section** (strip the trailing "…" continuation marks). Never merge slides into a "natural" verse on your own guess. Only when the SAME text repeats on several slides (e.g. a refrain after each verse) make it ONE `Chorus` section and replay it via `arrangement` (e.g. `["Verse 1","Chorus","Verse 2","Chorus"]`). Unlabeled, non-repeating slides get sequential `Verse N` labels; do not call something a Chorus/Bridge without the repetition evidence. Scripture/liturgy pages sitting between song slides are separate text slides, not song sections.

```
POST /api/v1/songs
{"song": {"title": "...", "author": "...", "song_key": "G", "chordpro_source": "..."}}
```
`chordpro_source` is ChordPro. Rules:
- NO blank lines anywhere in `chordpro_source` (not between sections either): the parser turns every blank line into an empty `none` section that shows up as a blank slide and breaks `arrangement`. Join sections with a single `\n`. The dry run's `warnings` flags any you missed.
- Every section needs its own label: two sections both labelled `Verse 1` are refused (`422`), because the arrangement and the song page find sections by label. A refrain that repeats is ONE section replayed through `arrangement`, not a copy.
- `arrangement` labels must match section labels exactly (`Chorus`, not `Coro`).
- Wrap each section: `{sov: Verse 1}` ... `{eov}`, `{soc}` ... `{eoc}` for chorus, `{sob: Bridge}` ... `{eob}` for bridge. Use English labels (Verse 1, Chorus, Bridge, Pre-chorus, Intro, Outro).
- Chords inline before the syllable they sit over: `[G]Amazing [C]grace`. Chords-over-lyrics in the PDF: move each chord to the character column of the lyric beneath it.
- Chords-only lines (intro/instrumental): `[G]    [C]    [D]    [G]` (pad each chord by its width + ~3 spaces).
- A repeated block: add `{comment: x2}` after it. Do not write literal `//`.
- Lyrics only (no chords): same structure, no brackets.
- Optional: `capo` (0-11), `copyright_line`, `ccli_song_number`, `copyright_status` (`copyrighted|public_domain|unknown`, default unknown), `arrangement` (array of section labels in play order).

## Text slide payload
```
POST /api/v1/text_slides
{"text_slide": {"title": "...", "tags": ["confession"], "font_size": 40, "text_align": "left", "vertical_align": "top", "font": "sans",
                "text_color": "#ffffff",
                "pages": [{"body_markdown": "CONFESSION OF SIN\n*leader line*\n***people line***\n\n~(Psalm 25:6-8)~"}]}}
```
All fields are in `docs/import_api.md`: `font_size`, `line_height` (`1.0|1.15|1.5|2.0`), `text_align`, `vertical_align`, `font`, the look (`bg_type` `solid|gradient`, `bg_color`, `bg_color2`, `bg_gradient_angle`, `text_color`) and auto-advance (`auto_advance_seconds`, `auto_advance_transition`, `auto_advance_loop`).
- One logical slide spanning several projected screens = several `pages`.
- Tags are free-form, lower-case (e.g. `call-to-worship`, `confession`, `assurance`, `benediction`, `creed`, `prayer`, `lords-supper`, `catechism`).
- `scripture` is ONLY for slides that are purely a scripture reading with no liturgical role (e.g. a "Psalm 102:25–27" reading between song verses). A slide titled as a liturgy element ("Call to Worship", "Confession of Sin", "Assurance of the Gospel", "The Lord's Supper", "Benediction", etc.) gets that element's tag and NOT `scripture`, even when its text is quoted from scripture.
- **Match the PDF's look, not just its text.** Never send the defaults (auto size, centered) on a guess. Measure the deck:
  - `docker cp` the PDF and `.kiro/skills/corobook-import/pdf2md.rb` into `corobook-next-web-1:/tmp/`, then
    `docker exec corobook-next-web-1 sh -c 'cd /rails && bundle exec ruby -e "load \"/tmp/pdf2md.rb\"; p page_layout(\"/tmp/x.pdf\", N); puts page_md(\"/tmp/x.pdf\", N)"'`.
  - `page_layout` -> `size_pt` (pt on Corobook's 540 pt canvas, from the body text size vs page height), `align`, `valign` and `text_color` (the body text's colour). Use the most common value across a slide's pages, snap the size to `Corobook::FontSize::OPTIONS`, and send them as `font_size`, `text_align`, `vertical_align`, `text_color`.
  - Background: look at the rendered page. A solid colour other than black -> `bg_color`; a gradient -> `bg_type: "gradient"` with both colours and the angle. A photo or picture background can't be set over the API (it needs an upload in the slide editor): import the text, then tell the user which slides need their image added by hand.
  - Line spacing: only set `line_height` when the PDF's lines are clearly tighter or looser than normal; otherwise leave it out.
  - Auto-advance only when the user asks for it (e.g. an announcements loop before the service): `auto_advance_seconds` per page.
  - `page_md` -> the page's markdown with the PDF's own line breaks, `*italic*` / `***bold italic***` runs as in the PDF (liturgy: leader italic, congregation bold italic), the heading as a plain same-size line (NOT `# Heading`, which renders larger), verse superscripts as Unicode superscripts (⁷ ¹¹), the reference as its own paragraph, and ligature gaps repaired (`af icted`). Literal `*` is escaped.
  - Render a few pages to compare visually: `pdftoppm -f N -l N -r 20 -png` (deck text is often white on a transparent/black page; view the PNG with the file reader).
- Small text: `~text~` shows a line or phrase small and dimmed (~0.4 of the body on the projector). Use it for lines the PDF sets much smaller than the body, like references and footnotes; `page_md` does this for you. `~~text~~` is strikethrough, and a literal tilde is `\~`.
- `font_size` is per slide, not per page. If one page of a slide is set at a different size in the PDF (e.g. a 49 pt page in a 40 pt creed), say so in the confirmation and offer to make that page its own slide.
- Each newline in `body_markdown` is a line break on screen; a blank line starts a new paragraph.

## Example call
```
curl -sS -X POST "$BASE/api/v1/songs" -H "Authorization: Bearer $COROBOOK_TOKEN" \
  -H "Content-Type: application/json" -d @payload.json
```
Write payloads to files under `$KIROCREW_SCRATCH` (avoids shell-quoting lyrics with apostrophes) and delete them afterwards. For a batch, loop in Python (`urllib.request`), not a zsh `for` loop: zsh does not word-split `set -- $pair`, so the requests silently go out empty.

## Errors
`401` bad/missing token, `403` user is not admin/editor, `404` not found or another church's record, `409` duplicate title (create, or a rename on PATCH), `422` invalid (see `messages`; e.g. a duplicate section label, a bad colour, `bg_type: "image"` without an uploaded image).
