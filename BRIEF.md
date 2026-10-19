# Corobook — Rewrite Brief (Rails 8)

**Audience:** An autonomous agent (Kiro Crew) or developer executing this rewrite end-to-end.
**Source of truth for behavior:** the legacy app at `/Users/blablo/Development/corobook` (Rails 4.0, MySQL).
**Target app location:** `/Users/blablo/Development/corobook-next` (already scaffolded: Rails 8.1.4, PostgreSQL, Tailwind, Solid Cache/Queue/Cable).

Do **not** modify the legacy repo. Commit to the new app after each green step. Never touch its `master`.

---

## 1. What the product is

Corobook is a **church/choir song manager + live worship projection** app (Spanish UI). A church stores songs (lyrics + chords), assembles songbooks (dated setlists), and runs live presentations where slides are projected to a screen. The rewrite adds **real-time sync**: while the projector shows lyrics-only slides to the congregation, musicians follow along on their own devices **with chords**, synced to the operator's current slide/verse.

---

## 2. Decisions already made (do not re-litigate)

- **Stack:** Rails 8 + Hotwire (Turbo + Stimulus) + PostgreSQL + Tailwind + ViewComponents + Devise + Pundit.
- **Database runs in Docker** (Postgres 16 container); Ruby/Rails run locally (installed via `mise`, Ruby 3.3.12, Rails 8.1.4).
- **Live sync:** Turbo Streams over ActionCable, backed by **Solid Cable** (no Redis).
- **Public follow link:** a live presentation is followable at a **hard-to-guess token URL** (e.g. `/live/:token`) with **no login**. Operator controls require login + Pundit authorization.
- **Transposition:** build the parser around a **chord AST** so transposition (shift chords by N semitones) can be added. Implement the AST + parser now; the transpose UI can come later, but the model must support it.
- **Auth migration:** use Devise so existing bcrypt `encrypted_password` hashes keep working for current users.
- **Mobile:** NOT in this scope. Web-first. (If pursued later: PWA or Hotwire Native, staying on this Rails codebase.)

---

## 3. Domain model (port from legacy `db/schema.rb`, MySQL → Postgres)

14 tables. Multi-tenant: almost everything is scoped by `church_id`.

| Model | Key fields | Associations / notes |
|---|---|---|
| **Church** | name | has_many presentations, settings, diapos, users, anniversaries. Tenant root. |
| **User** | email, encrypted_password (Devise), name, group_id, role (int), church_id | belongs_to group, church; has_many songs, votes; has_many groups through user_groups. |
| **Group** | name, role (int) | has_many users, user_groups, songs. `add_to_group(user, role=1)` → first member gets role 9. |
| **UserGroup** | user_id, group_id, role (int) | join. |
| **GroupCollaborator** | email, user_id, name, role (int), group_id | lightweight collaborator record. |
| **Role** | name, resource_type/id (polymorphic) | legacy rolify table. See §5 — replace rolify with plain enum; keep `admin` concept. |
| **Song** | title, author, lyric (text), user_id, link, reference, mood (int), order (string), church_id | belongs_to user, group; has_many songbook_songs, songbooks (through), votes. **Core logic — see §4.** |
| **Songbook** | title, fecha (date), church_id | has_many songs through songbook_songs. A dated setlist. |
| **SongbookSong** | song_id, songbook_id, order (int) | join; validates uniqueness of (songbook_id, song_id). |
| **Presentation** | fecha (datetime), church_id | has_many contents (ordered by position, acts_as_list), dependent destroy. `load_template` builds contents from `settings.presentation_template`. `songs_list` = comma-joined song titles. paginates_per 5. |
| **Content** | order, song_id, diapo_id, presentation_id, position | belongs_to presentation, song, diapo. `acts_as_list scope: :presentation`. A content is EITHER a song or a diapo (`thing` returns whichever is set). |
| **Diapo** | title, info (text, rich HTML), background (uploaded img), show_title (bool), church_id | a custom slide (announcement, image, etc.). Special title `'anniversaries'` renders the birthday list. |
| **Anniversary** | date (datetime), name, category, church_id, easy_date (int) | scope `current_month` (filter by month of `date`). Shown on the anniversaries slide. |
| **Setting** | church_id, songs_background (img), songs_case, songs_font_color (#FFFFFF), songs_text_bg_color, presentation_template, anniversaries_background (img) | per-church projection styling + default presentation template. One per church (`settings.first`). |
| **Vote** | song_id, user_id | belongs_to user, song. Song voting. |

Migration notes:
- Drop `attr_accessible` → use Rails strong parameters.
- Convert MySQL types to Postgres equivalents; `Anniversary.current_month` uses MySQL `MONTH(date)` — rewrite for Postgres (`EXTRACT(MONTH FROM date) = EXTRACT(MONTH FROM CURRENT_DATE)`).
- Image uploads (CarrierWave `BackgroundUploader` on Diapo/Setting) → **Active Storage** (S3 in prod, local in dev).
- Rich text (CKEditor on Diapo.info) → **Action Text (Trix)**.

---

## 4. The lyric/chord parser — THE core logic (port carefully, with tests)

Lyrics are stored as free text in `Song.lyric`. Format:
- Verse headers are lines wrapped in brackets: `[CORO]`, `[VERSO 1]`, `[PUENTE]`, etc.
- Under each header: alternating **chord lines** and **lyric lines** (chord line usually directly above its lyric line).
- `Song.order` is a comma-separated string naming the sequence verses are sung in, e.g. `"VERSO 1, CORO, VERSO 2, CORO"`. Verses can repeat.

Validation (`validate_sintax`): lyric must contain at least one `[...]` verse marker, else error on `order`.

**Chord-line detection heuristic (must replicate exactly):**
A line is considered a chord line if EITHER:
1. it matches **≥ 2** chord tokens, OR
2. chord characters make up **≥ 60%** of the non-whitespace characters.

Chord token regex (from legacy):
```
\b[CDEFGAB](?:#|b)?(?:m|maj|dim|aug|sus[24]?)?(?:7|9|11|13)?\b
```

**Methods to port (behavior-equivalent), from legacy `app/models/song.rb`:**
- `order_list` → `order.gsub(', ', ',').split(',')`.
- `hashed_lyric(show_chords=false)` → `{ "VERSE" => [{line:, type: :chords|:text}, ...] }`. Chord lines only included when `show_chords` true.
- `sorted_array_lyric(show_chords=false)` → array of `{label:, text:[...]}` in `order` sequence. **Repeat handling:** when the same verse repeats consecutively, instead of duplicating it, prepend/append slash marks (`/`, `//`, ...) to the first/last text line to indicate "repeat N times". (See legacy impl — Marshal deep-copy, slash count increments.)
- `diapo_mode(chords=false)` → `{ "VERSE" => "html with <br>" }`, lyrics-only by default (for projector slides).
- `clean_lyric` → lyric with chord lines stripped.

**New for the rewrite (chord AST + transposition):**
Instead of flagging lines as `:chords`/`:text` strings, parse chord lines into tokens with position, producing an AST like:
```
Verse(label) -> [ Line(type: :chords, chords: [Chord(root, quality, bass, col)]) | Line(type: :lyric, text) ]
```
Transposition = map each `Chord.root` up/down N semitones (respect sharps/flats, enharmonics). Renderers derive from the AST:
- **projector render:** lyrics only (congregation).
- **musician render:** chords + lyrics, optionally transposed.
- **print/show render:** chords over lyrics (the legacy `chordify2`/`<pre>` view).

Put this in a `LyricParser` service object (`app/services/lyric_parser.rb` or a `Lyric::` namespace) with **thorough unit tests** using real samples from `/Users/blablo/Development/corobook/songs.sql`. This is the highest-risk code — prove equivalence against legacy output before building UI on top.

---

## 5. Authorization (replace CanCan + rolify)

Legacy uses a role **integer ladder** on `User.role` plus rolify's `:admin` role:
- `1 = viewer`, `3 = song_manager`, `5 = songbook_manager`, `9 = admin` (helpers `is_viewer?`, `is_song_manager?`, `is_songbook_manager?`, `is_admin?`).
- Ability rules (from `app/models/ability.rb`):
  - Guests (not logged in): can **read** songs only.
  - Admin (`has_role? :admin`): manage everything.
  - Song manager (role ≥ 3): create songs; update/destroy songs of their own group(s); manage Songbook/Presentation/Diapo/Anniversary/Setting.
  - Songbook manager (role ≥ 5): manage Songbook/Presentation/Diapo/Anniversary/Setting; read songs.
  - Regular user: create songs; update/destroy songs of their group(s); read the rest.
  - All logged-in users: manage Group, GroupCollaborator, UserGroup.
- Song edit rule (`Song#editable_by?`): admin, OR user belongs to the same group as the song (song.user_id may be nil for legacy songs — group match is what counts).

**Rewrite:** model `role` as a Rails **enum** (`viewer:1, song_manager:3, songbook_manager:5, admin:9` — keep the integers for data compatibility) and implement the above as **Pundit policies** (SongPolicy, SongbookPolicy, PresentationPolicy, etc.). Keep guest read access to songs.

---

## 6. Live presentation sync (the headline new feature)

Legacy `/live` renders a **deck.js** slide deck server-side (fullscreen, FitText auto-sizing, per-church background/font from Settings). Projector shows **lyrics only**; slides are generated from each content's `sorted_array_lyric` (songs) or diapo HTML. Special diapo title `'anniversaries'` renders `current_month` birthdays.

**Rewrite target:**
- A **LiveSession** concept per presentation holding the current position: `content_id` + `verse_index` (which slide, which verse within a song). Generate a `token` (unguessable) for public follow URLs.
- **Three synchronized views**, all subscribed to a per-presentation ActionCable channel:
  1. **Projector** (`/live/:token/screen` or similar): fullscreen, congregation layout, **lyrics only**, per-church background/font/case/text-bg from Settings, big auto-fit text. No chords.
  2. **Musician** (`/live/:token`): same synced position, shows **chords + lyrics**, current + next-up preview, auto-scroll/highlight. Public (token), no login. Transposition control (per-device) is a later enhancement but design for it.
  3. **Operator** (authenticated): control panel — next/prev slide & verse, jump-to, live preview of what the projector shows. Updating position broadcasts a Turbo Stream to the channel; all followers re-render.
- **Late-join safe:** a client connecting fetches the current position so it syncs immediately.
- Replace deck.js with a Stimulus controller for navigation + Turbo Stream broadcasts. Keep per-church styling from Settings.

Legacy `format.js` sprinkles (vote add, songbook add/remove toggles) → replace with **Turbo Streams** (server-rendered partial swaps).

---

## 7. Feature inventory (controllers/routes to reproduce)

From legacy `config/routes.rb` + controllers:
- **Songs:** CRUD; `show`/`index`/`live` public; member `live`; collection `vote_add`, `songbook_add`, `songbook_remove`. Create assigns `user = current_user`, `group = current_user.group || groups.first`; blocks create if user has no group. Update filters out `user_id`/`group_id`.
- **Songbooks:** CRUD; member `send_email` (emails the songbook — Gmail SMTP in legacy; use Action Mailer).
- **Presentations:** CRUD (church-scoped, ordered by fecha desc, paginated); member `live` (public, layout-less); `load_template` from Settings; nested `contents` via accepts_nested_attributes; vote.
- **Diapos:** CRUD (custom slides, image bg, rich info).
- **Groups / UserGroups / GroupCollaborators:** CRUD (any logged-in user).
- **Anniversaries:** CRUD; `current_month` scope feeds the anniversaries slide.
- **Settings:** per-church projection styling + default presentation template editor.
- **Users:** Devise auth (database_authenticatable, registerable, recoverable, rememberable, trackable, validatable) + CRUD.
- **Home:** root `home#index`.

`current_church` helper scopes queries per tenant — reproduce it (e.g. from `current_user.church`, or church resolved from the live token for public views).

---

## 8. Data migration

- Legacy data dump: `/Users/blablo/Development/corobook/songs.sql` (MySQL, ~123 KB). Primarily songs; use it both for (a) seeding/importing real data and (b) as parser test fixtures.
- Write a one-off import task: parse the MySQL dump (or re-export as needed) and load into the new Postgres schema, preserving `encrypted_password` so Devise logins keep working.
- Verify a sample of migrated songs render identically (chords, verse order, repeats) under the new `LyricParser` vs legacy output.

---

## 9. Execution order (each step must end green + committed)

1. **Foundation:** confirm app boots; add `docker-compose.yml` (Postgres 16), point `config/database.yml` at it; `bin/rails db:prepare`. Add RSpec (or Minitest), Tailwind confirmed, importmaps. Commit.
2. **Schema & models:** migrations for all 14 tables (Postgres types), associations, `role` enum, strong params, church scoping. Model specs. Commit.
3. **LyricParser + chord AST + transposition:** port all parsing methods, add AST + transpose, unit tests vs real `songs.sql` samples. Commit. *(Highest risk — do before UI.)*
4. **Auth:** Devise wired to reuse legacy bcrypt hashes; Pundit policies per §5. Specs. Commit.
5. **Core CRUD + Hotwire:** songs, songbooks, groups, settings, anniversaries, votes; Turbo Streams replacing `format.js`; Trix for diapo info; Active Storage for images. Commit per resource.
6. **Live presentations:** LiveSession + token follow URL + Solid Cable channel + three synced views (projector / musician+chords / operator). Commit.
7. **Data migration:** import task from `songs.sql`; verify render equivalence on samples. Commit.
8. **Polish:** mailers (songbook send_email), seeds, README/setup docs, deploy config.

---

## 10. Environment already provisioned on this machine

- `mise` installed (Homebrew); Ruby **3.3.12** global via mise.
- **Rails 8.1.4** gem installed.
- Homebrew **postgresql@16** installed but **service stopped** (DB will run in Docker per decision).
- Node 26, Docker 29 present.
- App scaffolded at `/Users/blablo/Development/corobook-next` with `--database=postgresql --css=tailwind`, including Solid Cache/Queue/Cable.

## 11. Open items to confirm with the user when reached
- Transposition UI timing (model supports it now; UI later).
- Email provider for `songbook#send_email` (legacy used Gmail SMTP).
- Whether to import legacy data now or build schema-first and import last (brief assumes import last, step 7).
