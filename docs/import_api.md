# Import API (v1)

Token-authenticated JSON API for creating songs and text slides (e.g. from a PDF read by an agent).
Content is created in the token user's church; the user must be an admin or editor.

## Issue a token

    docker exec corobook-next-web-1 bin/rails corobook:issue_api_token EMAIL=you@church.org NAME="pdf import"

The raw token (`cbk_...`) is printed once; only its digest is stored. Send it as `Authorization: Bearer <token>`.

## Endpoints

All bodies are JSON. Add `"dry_run": true` to any POST to validate without saving.

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/v1/songs?q=` | search title/author/lyrics (max 50) |
| POST | `/api/v1/songs` | `{song: {title, author, subtitle, reference, link, song_key, capo, copyright_line, ccli_song_number, copyright_status, chordpro_source, arrangement: []}}` |
| GET | `/api/v1/songs/:id` | full song (incl. `chordpro_source`, `arrangement`) |
| PATCH | `/api/v1/songs/:id` | partial update: send only the fields to change |
| GET | `/api/v1/text_slides?q=` | search the slide library |
| GET | `/api/v1/text_slides/:id` | full slide (incl. `pages`) |
| PATCH | `/api/v1/text_slides/:id` | partial update; `pages`, when sent, replaces all pages |
| POST | `/api/v1/text_slides` | `{text_slide: {title, tags: [], pages: [{body_markdown}], ...layout, look and auto-advance fields below}}` |

PATCH responds `200` with the record and `changed` (field names); with `dry_run` it returns
`would_change` + `would_update` and saves nothing. Renaming onto another item's title is `409`.
Records of another church are `404`.

Responses: `201` created, `200` dry run (`would_create`), `409 duplicate` (same title in the church,
returns `existing`), `422 invalid` (`messages`), `401` bad token, `403` wrong role.

## What a song returns

Song responses (create, dry run, show, PATCH) carry the song as the parser reads it, so a dry run
can be checked before saving:

- `sections`: `[{label, kind, lines: [plain text]}]` in source order.
- `warnings`: mistakes that save fine but project wrong. An empty section (a blank line in
  `chordpro_source` becomes a blank slide; use no blank lines), or an `arrangement` label that names no
  section (the arrangement matches labels exactly).

Two sections with the same label (outside a replayed `{chorus}`) are refused with `422`: the
arrangement and the song page find sections by label, so the second one would be lost.

## Text slide fields

All optional on create; on PATCH send only what changes.

| Field | Values | Default |
| --- | --- | --- |
| `font_size` | pt on Corobook's 540 pt-tall canvas (PowerPoint scale), 10-200 | `null` = auto-fit |
| `line_height` | `1.0`, `1.15`, `1.5`, `2.0`: distance from one line to the next as a multiple of the font size (CSS line-height) | `null` = the slide default (`1.15`) |
| `text_align` | `left`, `center`, `right` | `center` |
| `vertical_align` | `top`, `center`, `bottom` | `center` |
| `font` | `sans`, `serif`, `condensed`, `mono` | `sans` |
| `bg_type` | `solid`, `gradient` (`image` needs an uploaded image: use the slide editor) | `solid` |
| `bg_color`, `bg_color2`, `text_color` | hex like `#112233` (`bg_color2` is the gradient's second colour) | `#000000`, `#1a1a2e`, `#ffffff` |
| `bg_gradient_angle` | 0-360 | `160` |
| `auto_advance_seconds` | 2-600: the pages turn by themselves every N seconds; `null` = off | off |
| `auto_advance` | `false` turns auto-advance off | |
| `auto_advance_transition` | `fade`, `cut` | `fade` |
| `auto_advance_loop` | `true`/`false`: start over after the last page | `true` |

Slide responses (create, dry run, show, PATCH) return these fields, `pages`, and `pages_html`: each
page rendered exactly as the projector shows it, to check the markdown before saving.

## Page markdown

- Each newline is a line break on screen; a blank line starts a new paragraph.
- `*italic*`, `**bold**`, `***bold italic***`.
- `~small text~`: small and dimmed (about 0.4 of the body on the projector), for references and
  footnotes. `~~text~~` is strikethrough.
- `\*`, `\~`, `\_` are literal characters.
- Raw HTML is escaped, never rendered.
