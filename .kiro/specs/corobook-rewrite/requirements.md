# Corobook Rewrite — Requirements

## Goal

Rewrite Corobook — a church/choir song manager and live worship projection app — on a
modern Rails 8.1 / PostgreSQL / Hotwire stack. The legacy Rails 4.0 app at
`/Users/blablo/Development/corobook` is a **read-only behavioral reference**: it defines
what the app must *do*, not how it must be built. All structure, schema, and code may
change. The hard constraints are: **data preservation** — the legacy songs in
`corobook/songs.sql` must import losslessly — and **behavioral fidelity** of what users
see on screen (correct lyrics, correct chords, correct transposition, correct live sync).

The app is **multi-tenant for two fully-isolated churches**: each church has its own songs,
sets, users, live sessions, and settings, with no cross-church data visibility.

The headline capability is **live sync** over a **presentation of mixed items** — songs and
text slides (statements, blessings, statement of faith, questions, sermon points). An
operator drives the set; a projector shows lyrics/slide-text only to the congregation;
musicians follow the same position with chords, in a key (and capo) of their own choosing —
in real time over Turbo Streams / Solid Cable. The genuinely distinctive combination (vs.
incumbents like Planning Center, which offers independent per-musician key but behind a
login) is **anonymous-token live position-follow with an independent key per follower**.

### Architecture decisions (validated against the category and the real data)

- **ChordPro is the single source of truth.** A song's lyrics+chords are authored and
  stored as ChordPro text (inline bracketed chords, e.g. `Yo soy la [G]sal de la [D]tierra`),
  parsed **once on save** into structured JSONB, from which every view (projector, musician,
  operator), transposition, and capo are derived. No re-parsing at render time. ChordPro is
  the de-facto editable interchange format (SongSelect/OnSong/Planning Center all import it).
- **The legacy column-aligned chords-above-lyrics format is NOT used for authoring.** It
  survives only as input to a one-time **migration converter** (legacy columns → ChordPro).
- **Legacy data reality (verified against `songs.sql`):** chord line immediately followed by
  its lyric line; chords positioned by column over the syllable; `//` inline markers denote
  repeats/choruses; **line endings are CRLF (`\r\n`)**; chord vocabulary includes suffixes,
  accidentals and malformed tokens (`Fm#`, `C°` sometimes stored as a space + combining
  ring). Legacy songs also carry **named section labels** (`[VERSE 1]`, `[CHOIR]`, `[BRIDGE]`)
  and an **arrangement/`order`** field (a comma-separated play sequence of those labels).
  The converter must handle all of this; the live app never touches the legacy format.

## Terminology

- **Church** — a tenant. Owns all songs, sets, users, live sessions, and settings. Two
  churches, fully isolated. Holds church-level settings including its **CCLI License #**.
- **User** — belongs to exactly one church, with a role of **admin** or **editor**
  (see Requirement 5). Public projector/musician viewers are NOT users — they hold a token.
- **Song** — belongs to a church. Fields: title, author/writer credit, optional subtitle,
  optional reference, optional link, optional `key` and `capo`, optional **copyright line**,
  optional **CCLI song number**, a **copyright status** (copyrighted / public-domain /
  unknown), plus the ChordPro source and its derived parsed form.
- **ChordPro source** — the lyric text in ChordPro syntax: inline bracketed chords (`[G]`,
  `[Em7]`), section environments (`{start_of_verse}`/`{sov}`…`{eov}`,
  `{start_of_chorus}`/`{soc}`…`{eoc}`, `{start_of_bridge}`/`{sob}`…`{eob}`) with optional
  labels (`{start_of_verse: Verso 1}`), metadata directives (`{key}`, `{capo}`, `{title}`,
  `{subtitle}`, `{comment}`), and any app-specific directive namespaced `x_corobook_…`.
  The song's single editable field.
- **Parsed lyric** — structured form derived from the ChordPro source: ordered **sections**,
  each with a **free-text label** (e.g. `Verso 1`, `Coro`, `Puente`) and a repeat/chorus
  flag, each an ordered list of **lines**, each line an ordered list of **segments**
  `{chord, text}` where `chord` may be null. Stored as JSONB. Views, transposition and capo
  read this, never the source text.
- **Arrangement** — an optional ordered sequence of a song's section labels defining play
  order (e.g. `Coro, Verso 1, Verso 2, Coro`). Live sync advances through the arrangement
  when present, else top-to-bottom.
- **Text slide** — a non-song presentable item: free-form text authored in lightweight
  markdown, carrying a **subtype** label (e.g. statement, blessing, statement of faith,
  question, sermon point, scripture, announcement) that can drive styling. One text-slide
  item holds one or more slides. No chords, no ChordPro.
- **Content library** — a church's reusable presentable content: its Songs and its reusable
  Text slides (statement of faith, standard blessings). Library items are referenced by many
  Sets.
- **Set** — a church's ordered list of **items**, prepared in advance and launchable as a
  live session. Each item is either a **Song**, a **library Text slide**, or a **one-off
  inline Text slide** local to that Set (e.g. this week's sermon points). (Unifies the legacy
  songbook/presentation/diapo concepts into one noun.)
- **Live session** — an operator-driven run through a Set: a small persisted record of the
  current item and current section/slide, broadcast to followers in real time.
- **Projector view** — the current item rendered for the congregation: song lyrics only (no
  chords, plus a copyright notice when required) or a text slide's content, in large,
  high-contrast type. Public, reached by an unguessable token.
- **Musician view** — for a song, lyrics with chords, transposable and capoable per-follower;
  for a text slide, the same content the projector shows (so musicians know where the service
  is). Follows the operator's position. Public, reached by an unguessable token.
- **Operator view** — the control surface: drive position across items, blank the screen,
  preview the next item/section before showing it, jump to or add an item mid-service.

---

## Requirements

### 1. Song authoring and storage

**User story:** As an editor, I want to author songs in ChordPro text, so that chords bind
unambiguously to syllables and I can paste or edit a whole song as plain text.

**Acceptance criteria:**
1. WHEN an editor submits a song with a title and a ChordPro source THE SYSTEM SHALL persist
   the ChordPro source verbatim as the editable source of truth, scoped to the editor's church.
2. WHEN a song is saved THE SYSTEM SHALL parse the ChordPro source once into the structured
   parsed-lyric JSONB and store it alongside the source.
3. WHEN a song is saved THE SYSTEM SHALL parse without losing any chord, lyric, section, or
   repeat marker (parse-completeness); full round-trip equivalence is asserted only during
   migration (see Requirement 11), not on every save.
4. IF the ChordPro source contains an unrecognized or malformed chord token THEN THE SYSTEM
   SHALL retain it as a chord segment and SHALL NOT raise an error.
5. IF the source contains an unknown directive THEN THE SYSTEM SHALL ignore it without error;
   IF the app emits any app-specific directive THEN it SHALL be namespaced `x_corobook_…`.
6. IF a section contains chord-only lines (chords with no lyric text) THEN THE SYSTEM SHALL
   parse it without error.
7. WHEN a song has no title THE SYSTEM SHALL reject the save with a validation error.
8. WHEN the source declares `{key}` and/or `{capo}` THE SYSTEM SHALL parse and persist them
   as the song's key and capo metadata.
9. THE SYSTEM SHALL store optional `copyright_line`, `ccli_song_number`, and a copyright
   status (copyrighted / public-domain / unknown) per song (see Requirement 9 — CCLI).

### 2. Lyric parsing (ChordPro → structured form) and legacy conversion

**User story:** As the system, I want one correct ChordPro parser producing a structured
lyric, so every view is derived without re-parsing and transposition is a pure function —
plus a separate one-time converter to bring legacy songs into ChordPro.

**Acceptance criteria:**
1. WHEN the source contains inline bracketed chords (`[chord]`), including mid-word
   (`char-i-[D]ot`), THE SYSTEM SHALL bind each chord to the character position immediately
   following its bracket.
2. WHEN a line has text with no chords THE SYSTEM SHALL parse it as a text-only segment.
3. WHEN the source contains section environments (`{sov}`/`{eov}`, `{soc}`/`{eoc}`,
   `{sob}`/`{eob}`), with or without a label, THE SYSTEM SHALL record the section's free-text
   label and repeat/chorus flag as metadata distinct from lyric text.
4. THE SYSTEM SHALL treat `{chorus}` as a chorus-**replay** directive (re-emit a previously
   defined chorus), per the ChordPro standard — NOT as a chorus-start marker. IF replay is
   not implemented in v1 THEN the directive SHALL be recorded as a replay reference without
   error, never silently treated as a new section.
5. WHEN no explicit section directive is present THE SYSTEM SHALL treat blank-line-separated
   groups as sections (fallback only).
6. WHEN the source contains a `{transpose}` directive THE SYSTEM SHALL honor it as the song's
   baseline transposition or record it without error (behavior fixed in design).
7. THE SYSTEM SHALL normalize CRLF to LF before parsing and parse identically for either.
8. **Legacy converter:** WHEN given a legacy column-aligned lyric blob THE SYSTEM SHALL
   produce an equivalent ChordPro source — mapping column-positioned chords to the syllable
   beneath them (handling **tab characters** and **Unicode column width** for accented caps
   like `CORAZÓN`), converting inline `//` to the appropriate repeat/chorus directive,
   carrying legacy section labels into section labels, and the legacy `order` field into an
   arrangement — tolerating malformed chord tokens (`Fm#`, combining-ring `C°`).
9. THE SYSTEM SHALL convert and then parse every song in `songs.sql` without error
   (validated during migration — see Requirement 11).

### 3. Rendering — three audiences

**User story:** As a worship team, we each want the right view of the current item, so the
congregation sees clean lyrics or slide text while musicians see chords in their key.

**Acceptance criteria:**
1. WHEN the projector view renders a **song** THE SYSTEM SHALL display lyric text only — no
   chords, no repeat markers — in large, high-contrast type sized for projection.
2. WHEN a copyrighted song is projected THE SYSTEM SHALL display its copyright/license notice
   (title, writer, copyright line, "Used By Permission. CCLI License #<church license>") at
   least once per song; IF the song's copyright status is public-domain THEN the notice
   SHALL be omitted (see Requirement 9).
3. WHEN the musician/operator view renders a **song** THE SYSTEM SHALL display chords
   positioned above their syllables, with repeat/chorus sections visually distinguished.
4. WHEN the musician/operator view renders a **song** THE SYSTEM SHALL display the current key
   (and capo, if set).
5. WHEN the projector view renders a **text slide** THE SYSTEM SHALL display the slide's
   rendered markdown in large, high-contrast type, styled per its subtype; the musician view
   SHALL display the same content (no chord staff). A text slide carries no copyright notice.
6. THE SYSTEM SHALL derive all song views from the stored parsed JSONB without re-parsing the
   ChordPro source at render time.
7. WHEN a lyric line, verse, or slide is long THE SYSTEM SHALL auto-fit projector text to the
   viewport so it does not overflow, and SHALL expose an operator control to scale projector
   type up/down live.

### 4. Transposition and capo

**User story:** As a musician, I want to transpose and capo a song to a shape I can play, so
I can follow the set without rewriting chords.

**Acceptance criteria:**
1. WHEN a musician selects a transpose interval (semitones) THE SYSTEM SHALL shift every
   chord in the parsed form by that interval. WHEN a musician selects a **target key** THE
   SYSTEM SHALL shift relative to the song's stored `{key}`; IF no source key is known THEN
   only semitone-shift SHALL be offered.
2. THE SYSTEM SHALL preserve chord quality and extensions when transposing (`Em7`, `C°`,
   `F#` map to correctly spelled targets).
3. WHEN a musician sets a **capo** (0–11) THE SYSTEM SHALL re-voice displayed chord shapes
   accordingly while indicating the sounding key is unchanged.
4. IF a chord token is unrecognized THEN THE SYSTEM SHALL leave it unchanged rather than
   mangling it.
5. THE SYSTEM SHALL compute transposition and capo as pure functions over the parsed form,
   with no database mutation required to preview.
6. WHEN transposition or capo is applied THE SYSTEM SHALL affect only the musician/operator
   views; the projector (lyrics only) SHALL be unaffected.
7. THE SYSTEM SHALL support a per-song stored **preferred key** (default for everyone) AND a
   per-follower **ephemeral override** that is independent of the operator and other
   musicians (D1 = both).

### 5. Authentication and authorization (per church)

**User story:** As a church admin, I want tiered access scoped to my church, so editors can
manage our library and admins can manage our users, with no access to the other church.

**Acceptance criteria:**
1. THE SYSTEM SHALL authenticate users with a secure password mechanism (Rails 8
   authentication or an equivalent vetted gem).
2. THE SYSTEM SHALL model two roles — **admin** and **editor** — with no inheritance ladder.
   Editors manage the song/set library; admins additionally manage the church's users and
   settings.
3. WHEN a user attempts an action outside their role THE SYSTEM SHALL deny it.
4. THE SYSTEM SHALL scope every authenticated action to the user's church; a user SHALL
   never see or modify another church's songs, sets, users, sessions, or settings.
5. THE SYSTEM SHALL map legacy users into a church with an admin/editor role during
   migration, with no user left unmapped.
6. THE SYSTEM SHALL allow projector and musician views to be reached via an unguessable
   token WITHOUT authentication (see Requirement 6).

### 6. Live sync — operator, projector, musician

**User story:** As an operator, I want to drive a live set so the projector and every
musician's device follow my current item and position in real time, and I can control the
service as it actually unfolds.

**Acceptance criteria:**
1. WHEN an operator starts a live session for a Set THE SYSTEM SHALL create a session record
   holding the current item and current section/slide, scoped to the operator's church.
2. WHEN the operator advances or rewinds THE SYSTEM SHALL move by **section/slide** (following
   a song's arrangement when present, or a text slide's slide order) and broadcast the new
   position to all connected followers with human-imperceptible delay (soft target ~1 s;
   correctness under reconnect takes priority over raw latency).
3. THE SYSTEM SHALL expose the projector and musician views each via its own unguessable
   public token; possession of the token is the only access requirement, and tokens SHALL be
   revoked/expired when the session ends.
4. WHEN a projector or musician client connects or reconnects mid-session (late join) THE
   SYSTEM SHALL immediately sync it to the session's current item and position without an
   operator action.
5. WHEN the operator changes the current item THE SYSTEM SHALL update all followers and reset
   position to that item's start.
6. WHEN a musician has selected a key/capo THE SYSTEM SHALL preserve that choice across
   position and item changes, independent of the operator and other musicians (applies while
   a song is current; ignored on text-slide items).
7. IF a follower's connection drops THEN the projector SHALL **freeze on the last shown
   slide** — never showing an error, blank, or reconnecting spinner to the congregation — and
   SHALL auto-reconnect and re-sync to current position when the network returns.
8. WHEN the operator wants to blank the screen THE SYSTEM SHALL provide an instant
   **blank/black projector toggle** (and restore) as a first-class control.
9. THE SYSTEM SHALL let the operator **preview** the next item/section on their own view
   without pushing it to the projector, and SHALL indicate what is currently live vs. staged.
10. WHEN a service goes off-plan THE SYSTEM SHALL let the operator **jump to any item** already
    in the Set (changing the current item/section live). Spontaneous mid-service **add** of an
    item not in the Set is out of scope for v1 (it would mutate the reusable Set template —
    see design Medium model); operators pre-build the Set, sermon slides included.
11. IF the operator's own device reloads mid-session THEN THE SYSTEM SHALL restore them to the
    live session at its current item and position (session state is the persisted DB record, D3).

### 7. Text slides and Sets (presentation library)

**User story:** As an editor, I want to build an ordered Set of mixed items — songs and text
slides (statements, blessings, statement of faith, questions, sermon points) — so I can
prepare a whole service and launch it live.

**Acceptance criteria:**
1. THE SYSTEM SHALL support a **Text slide** item: one or more slides of lightweight-markdown
   content with a **subtype** label (statement, blessing, statement of faith, question,
   sermon point, scripture, announcement, …) that can drive styling. Text slides carry no
   chords and no ChordPro.
2. THE SYSTEM SHALL support **reusable** library text slides (referenced by many Sets) AND
   **one-off inline** text slides local to a single Set (e.g. this week's sermon points).
3. WHEN an editor creates a Set THE SYSTEM SHALL store an ordered list of **items**, each a
   church Song, a library Text slide, or an inline Text slide.
4. WHEN an editor reorders items in a Set THE SYSTEM SHALL persist the new order.
5. WHEN an editor launches a Set THE SYSTEM SHALL seed a live session's ordered item list
   from it.
6. THE SYSTEM SHALL scope songs, slides, and Sets to the editor's church.
7. THE SYSTEM SHALL migrate legacy songbook/presentation groupings into Sets; legacy
   diapo/anniversary/settings/CKEditor/votes/groups tables SHALL NOT be migrated.
8. The item model SHALL be extensible so a future **imported-deck** item type (Keynote /
   PowerPoint, rendered to per-slide images — see Out of scope) can be added without
   reworking Sets or live sync.

### 8. Search and browse

**User story:** As any user, I want to find a song quickly by title, author, or lyric text,
so I can add it to a Set or edit it.

**Acceptance criteria:**
1. WHEN a user searches a term THE SYSTEM SHALL match against title, author, and lyric text
   within their church and return matches ordered by relevance or title.
2. THE SYSTEM SHALL provide an alphabetical/paginated browse of the church's library.
3. A simple `ILIKE` search is sufficient for the expected corpus size; no full-text index is
   required in v1.

### 9. Multi-tenancy and CCLI compliance

**User story:** As a church admin, I want my church's data isolated and my CCLI obligations
supported, so we stay compliant and separate from the other church.

**Acceptance criteria:**
1. THE SYSTEM SHALL use one consistent integer `church_id` association on every scoped model
   (songs, sets, users, live sessions, usage events, settings).
2. WHEN any record is queried THE SYSTEM SHALL return only records in the current church's
   scope; there SHALL be no cross-church data visibility.
3. THE SYSTEM SHALL store per church: name and **CCLI License #**.
4. **(CCLI — MUST)** For copyrighted songs, THE SYSTEM SHALL be able to render the copyright
   notice on projection (once per song) and in any print/export (under each song), using the
   church's CCLI License #; public-domain songs SHALL omit it. *(Research, not legal advice;
   the binding text is each church's signed CCL Terms of Agreement.)*
5. **(CCLI — usage)** WHEN a song becomes the current song in a live session THE SYSTEM SHALL
   record a **usage event** (song id, CCLI song number snapshot, title, author, session id,
   timestamp, church id), deduplicated to one use per song per session.
6. **(CCLI — report)** THE SYSTEM SHALL produce a usage report (CSV export) over a date range
   — CCLI song number, title, author(s), count of uses — scoped to the church and excluding
   public-domain songs. *(Capture in v1; export may be a fast-follow.)*
7. THE SYSTEM SHALL NOT build SongSelect import or CCLI auto-reporting in v1 (SongSelect TOU
   conflicts with public follow-token exposure; no public auto-report API exists). Deferred
   with a dedicated TOU review if ever pursued.

### 10. Non-functional requirements

1. **Testing:** Minitest with Capybara/Selenium system tests (the project's configured stack).
   Parser, converter, transposer/capo, and live-sync broadcasting SHALL have unit/integration
   coverage; the three views and the live follow flow SHALL have system tests.
2. **Real-time transport:** Turbo Streams over Solid Cable (Action Cable); no third-party
   realtime service. The persisted session row is the source of truth; Cable carries updates.
3. **Accessibility:** the public projector and musician views SHALL meet strong contrast and
   projection legibility; authenticated admin/editor screens SHALL use sensible contrast
   (best-effort, no formal WCAG AA audit required in v1).
4. **Security:** follow tokens SHALL be cryptographically unguessable and revocable on session
   end; public views SHALL expose no editing or administrative capability; cross-church
   isolation SHALL be enforced server-side, not merely in the UI.
5. **Performance:** render, transpose and capo SHALL be derived from parsed JSONB without
   re-parsing; live position broadcast SHALL feel instantaneous (~1 s soft target).
6. **Data integrity:** migration SHALL be idempotent and verifiable (round-trip check on
   every imported song).

### 11. Data migration (sequenced last)

**User story:** As the owner, I want all legacy songs and sets imported losslessly into the
right church, run as the final step, so the rewrite launches with the real library.

**Acceptance criteria:**
1. THE SYSTEM SHALL import every song from `corobook/songs.sql` with title, author, reference,
   link, order (→ arrangement), and section labels preserved, converting the legacy lyric to
   a ChordPro source, into the designated church.
2. WHEN a song is imported THE SYSTEM SHALL convert it to ChordPro, parse it, and assert a
   successful **round-trip**; IF any song fails to convert or round-trip THEN THE SYSTEM SHALL
   report it rather than silently dropping or corrupting it.
3. THE SYSTEM SHALL default each imported song's copyright status to **unknown** (not © and
   not public-domain) for later per-song classification; it SHALL NOT assume CCLI coverage.
4. THE SYSTEM SHALL map legacy users into a church with an admin/editor role, with no record
   unmapped.
5. THE SYSTEM SHALL read from the SQL dump (and/or a live legacy DB) as the source of truth,
   NOT the stale committed `schema.rb`.
6. Migration SHALL be the LAST implementation step, after application behavior is built and
   tested against synthetic/sample data.

---

## Resolved decisions

- **D1 — Transposition persistence:** BOTH — per-song stored `{key}`/preferred key, plus a
  per-follower ephemeral override (Req 4.7).
- **D2 — Multi-tenancy:** IN — two fully-isolated churches, consistent `church_id` scoping
  (Req 9). No self-service signup, billing, subdomains, or cross-tenant admin in v1.
- **D3 — Live-session persistence:** a small persisted DB record (current item + section/slide)
  is the source of truth; broadcast over Solid Cable. Survives operator reload and server
  restart (Req 6.11).
- **D4 — Naming:** one concept, **Set** — an ordered list of items (songs + text slides),
  launchable live (Req 7).

## Deferred to a later version (designed-for, not built in v1)

- **Imported presentation decks** — import sermon slides from Keynote / PowerPoint (and
  similar), rendered to per-slide images and added to a Set as an imported-deck item. The
  item model (Req 7.8) must leave room for this so it is an addition, not a refactor.
- **Media on text slides** — background images/video and image slides.
- **Usage-report CSV export** — capture in v1 (Req 9.5); export may be a fast-follow (Req 9.6).

## Explicitly out of scope (not planned)

SongSelect import; CCLI auto-reporting; streaming license / online broadcast; Nashville-number
charts; auto-scroll in the musician view (operator-driven follow replaces it); legacy
diapo/anniversary/announcement/CKEditor/votes/groups subsystems; full-text search indexing;
enterprise RBAC / role inheritance.
