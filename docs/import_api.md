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
| POST | `/api/v1/songs` | `{song: {title, author, song_key, capo, copyright_line, ccli_song_number, copyright_status, chordpro_source, arrangement: []}}` |
| GET | `/api/v1/songs/:id` | full song (incl. `chordpro_source`, `arrangement`) |
| PATCH | `/api/v1/songs/:id` | partial update: send only the fields to change |
| GET | `/api/v1/text_slides?q=` | search the slide library |
| GET | `/api/v1/text_slides/:id` | full slide (incl. `pages`) |
| PATCH | `/api/v1/text_slides/:id` | partial update; `pages`, when sent, replaces all pages |
| POST | `/api/v1/text_slides` | `{text_slide: {title, tags: [], pages: [{body_markdown}], font_size, text_align, vertical_align, font}}` |

PATCH responds `200` with the record and `changed` (field names); with `dry_run` it returns
`would_change` + `would_update` and saves nothing. Renaming onto another item's title is `409`.
Records of another church are `404`.

Responses: `201` created, `200` dry run (`would_create`), `409 duplicate` (same title in the church,
returns `existing`), `422 invalid` (`messages`), `401` bad token, `403` wrong role.

Slide layout (optional, defaults: auto size, centered): `font_size` in pt on Corobook's 540 pt-tall canvas
(PowerPoint scale; nil = auto-fit), `text_align` `left|center|right`, `vertical_align` `top|center|bottom`,
`font` `sans|serif|condensed|mono`. Page markdown: each newline is a line break; `*italic*`, `**bold**`, `***both***`.
