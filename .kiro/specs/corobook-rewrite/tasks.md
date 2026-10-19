# Corobook Rewrite — Tasks

Ordered, incremental implementation plan. Each task builds on prior ones, ends **green**
(build + relevant tests pass), and is committed before the next. Stack: Rails 8.1.4, Ruby
3.3.12, Postgres, Hotwire (Turbo + Stimulus via importmap), Tailwind, Solid Cache/Queue/Cable,
Minitest + Capybara. Migration is LAST. Never push to `master`/protected branches.

Conventions: commits follow Conventional Commits (`feat:`, `fix:`, `test:`, etc.). Every task
with code includes its own tests. `_Requirements:_` cites the requirement IDs each task
implements; `_Design:_` cites the design section.

---

## 1. Foundation

- [x] 1.1 Add a `docker-compose.yml` with a Postgres 16 service (localhost-bound), and a
  `.env`/`config/database.yml` wiring for dev/test. Verify `bin/rails db:prepare` creates
  `corobook_next_development` and `_test`.
  _Requirements: 10.2_ _Design: §1, §11.1_
- [x] 1.2 Create the initial migration enabling Postgres extensions `citext` and `pg_trgm`
  via `enable_extension`. Verify locally (`db:migrate` + `SELECT extname`) AND that both
  survive a `schema.rb` dump/load — i.e. `bin/rails db:test:prepare` in CI leaves them
  enabled (so `citext` columns and `pg_trgm` indexes in later tasks don't fail on a fresh CI DB).
  _Design: §2.1, §8_
- [x] 1.3 Uncomment `bcrypt` in the Gemfile and add a markdown gem (`commonmarker`, pinned);
  `bundle install`. Confirm `has_secure_password` is available and `commonmarker` renders.
  _Design: §4 (Rails 8 specifics), §5_
- [x] 1.4 **Adapt** the existing `.github/workflows/ci.yml` (do NOT add a new one — `test` and
  `system-test` jobs already exist): confirm both run against a Postgres service; **add a
  headless-Chrome/Chromedriver setup step to the `system-test` job** (`ruby/setup-ruby` does
  not provide a browser, so Selenium would otherwise fail); confirm the extension migration
  (1.2) runs in the CI DB. Generate the system-test base class
  (`test/application_system_test_case.rb`) if absent and add one smoke system test hitting a
  health route. Acceptance = **CI green on a PR** and `bin/rails test:system` runs headless
  locally.
  _Requirements: 10.1_ _Design: §10, §11.1_

## 2. Tenancy and authentication

- [x] 2.1 Generate `Church` (`name`, `ccli_license_number`) and seed two churches. Model test:
  valid church persists; `ccli_license_number` optional.
  _Requirements: 9.1, 9.3_ _Design: §2.1_
- [x] 2.2 Generate `User` (`church_id`, `email citext`, `password_digest`, `role` string+check
  `admin|editor`) with `has_secure_password`, `belongs_to :church`, unique index
  `(church_id, email)`, Rails `enum :role`. Tests: same email in two churches both valid;
  password auth works; role enum values constrained by DB check.
  _Requirements: 5.1, 5.2, 9.1_ _Design: §2.1, §3.1_
- [x] 2.3 Add `Current` (`ActiveSupport::CurrentAttributes` with `church`, `user`) and an
  `ApplicationController` `before_action` that sets them from the session. Integration test:
  two sequential requests as different-church users do not leak `Current.church` between them.
  _Requirements: 5.4_ _Design: §3.2_
- [x] 2.4 Build sessions controller + church-picker login view (`GET/POST /login`,
  `DELETE /logout`): choose church, then email+password resolve against that church's users.
  System test: same email in both churches logs into the chosen one.
  _Requirements: 5.1, 5.4_ _Design: §3.1, §9_
- [x] 2.5 Add role authorization helpers (`require_admin`, `require_editor`) and a
  `TenantScoped` convention (all queries via `Current.church.<assoc>`). Add a model concern
  validating a child's `church_id` matches its parent. Add the **off-request tenancy test**:
  a code path invoked with `Current` unset (simulating a job/cable) that is passed a
  `live_session`/`church` explicitly still resolves the right church (design §3.2.3, the
  "critical" invariant). Tests: editor denied admin action; cross-church record access
  returns 404 (not 403); off-request church resolution works without `Current`.
  _Requirements: 5.2, 5.3, 5.4, 9.2_ _Design: §3.2, §3.2.3_

## 3. ChordPro parser, chord AST, transposer (pure core — no UI)

> The riskiest piece. Fully unit-tested before any UI touches it.

- [x] 3.1 Implement `Corobook::Chord` value object: parse a chord string into
  `{root, accidental, quality, extension, bass}`; `unparsed` flag on regex miss. Tests: parses
  `G`, `Em7`, `F#`, `C°`, `Dm/F`, `Cmaj7/G`; marks `Fm#`/garbage as unparsed.
  _Requirements: 2 (malformed tolerance), 4.4_ _Design: §4.4_
- [x] 3.2 Implement transpose + capo as pure functions on `Chord`: `transpose(semitones)`
  preserving quality/extension and choosing enharmonic spelling by target key;
  `capo(n)` display mapping; unparsed chords pass through unchanged. Tests: quality preserved,
  enharmonic spelling correct per key, unparsed unchanged, capo bounds 0..11.
  _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_ _Design: §4.4_
- [x] 3.3 Implement `Corobook::ChordPro::Parser` → `ParsedLyric` JSONB: CRLF normalize;
  inline `[chord]` binding to following text (incl. mid-word); `{title}/{subtitle}/{key}/
  {capo}/{transpose}/{comment}` meta; `{sov|soc|sob}`(+`eo*`) sections with labels;
  blank-line fallback; unknown directives ignored; never raises. Tests cover each rule +
  empty/chord-only sections + `{transpose}` captured in meta.
  _Requirements: 1.2, 2.1, 2.2, 2.3, 2.5, 2.6, 2.7, 1.4, 1.5, 1.6_ _Design: §4.2, §4.3_
- [x] 3.3b Add `{chorus}` replay materialization to the parser: copy the most recently defined
  chorus's lines into a section carrying `replay_of`; empty + `x_corobook_parse_warning` if no
  prior chorus. Tests: replay materializes concrete lines; missing-prior-chorus warns.
  _Requirements: 2.4_ _Design: §4.3_
- [x] 3.4 Implement ParsedLyric → ChordPro **serializer** and a round-trip assertion helper,
  honoring the whitespace contract (consecutive chords, chord-only lines, load-bearing
  spaces). Tests: round-trip a corpus of hand-written ChordPro fixtures byte-for-byte on
  lyric/chord content.
  _Requirements: 1.3, 11.2_ _Design: §4.3a_
- [x] 3.5 Implement `ParsedLyric` transform helpers: `transpose(parsed, semitones, capo)`
  (applying any meta `{transpose}` baseline FIRST, then the requested shift) and
  `plain_text(parsed)` (lyric text only, chords/directives stripped). Tests: baseline transpose
  applied before per-follower shift; transpose whole song; plain_text strips chords incl.
  mid-word rejoin.
  _Requirements: 4.1, 4.6, 8.1, 2.6_ _Design: §4.4, §4.3, §5, §8_

## 4. Songs: model, editor, three renderings (static)

- [ ] 4.1 Generate `Song` (all fields incl. `song_key`, `capo 0..11 check`, `copyright_line`,
  `ccli_song_number`, `copyright_status` string+check default `unknown`, `chordpro_source`,
  `parsed_lyric jsonb`, `plain_text`, `arrangement jsonb`). `before_save` parses source →
  `parsed_lyric` + `plain_text`; `pg_trgm` index on `plain_text`. Tests: save derives JSONB;
  malformed chord doesn't block save; title required.
  _Requirements: 1.1, 1.2, 1.7, 1.8, 1.9, 2 (tolerance)_ _Design: §2.1, §4.1_
- [ ] 4.2 Song CRUD controller + ChordPro editor view (textarea source + key/capo/copyright
  fields + **arrangement editor**: order the song's section labels, empty = section order),
  church-scoped, editor-gated. System test: create a song with a malformed chord — it
  persists, the editor shows the inline `x_corobook_parse_warning`, and the save is not
  blocked; set an arrangement and see it stored.
  _Requirements: 1.1, 1.6, 5.3, 4 (arrangement)_ _Design: §5, §9, §2.1_
- [ ] 4.3 Projector rendering partial (lyrics only, chords+`//` stripped, auto-fit Stimulus
  `fit` controller) + copyright notice, **including the full suppression rule**: render the
  notice (composed from `copyright_line` + church `ccli_license_number`) on the final section
  only for `copyright_status=copyrighted` with a license present; suppress it for
  public-domain, and for `unknown`-status or missing-license show an **editor-facing warning**,
  never a wrong notice. System tests: notice appears for copyrighted+licensed; absent for
  public-domain; suppressed + warning for unknown/missing-license.
  _Requirements: 3.1, 3.2, 3.7, 9.4_ _Design: §5, §7_
- [ ] 4.4 Musician rendering partial (chords above syllables, server-side transpose/capo to a
  chosen key via param, current-key badge, repeat sections distinguished). Tests: chords
  render; transpose changes displayed chords; unknown source key → semitone-only; **follower
  capo vs song `{capo}` precedence pinned** (follower choice overrides, documented).
  _Requirements: 3.3, 3.4, 4.1, 4.3, 4.7_ _Design: §4.4, §5, §6.3_

## 5. Text slides

- [ ] 5.1 Generate `TextSlide` (`church_id`, `title`, `subtype`, `body_markdown`, `reusable`,
  `set_id` null). Render markdown on read via a safe renderer with HTML escaping. Tests:
  reusable vs inline shape; markdown rendered + escaped.
  _Requirements: 7.1, 7.2_ _Design: §2.1, §5_
- [ ] 5.2 Text-slide CRUD (reusable library) + subtype-driven styling classes on projector and
  musician views. System test: create a "statement of faith" slide, see it styled.
  _Requirements: 3.5, 7.1_ _Design: §5_

## 6. Sets and search

- [ ] 6.1 Generate `Set` and `SetItem` (`position >=0 check`, `item_type` string+check,
  nullable `song_id`/`text_slide_id` with exactly-one CHECK + FKs, unique `(set_id, position)`).
  A Set `has_many` inline text slides (`reusable=false`) with `dependent: :destroy` so deleting
  a Set reaps its one-off slides. Model tests: exactly-one-FK enforced; cross-church item
  rejected; ordering; deleting a Set destroys its inline slides but not reusable ones.
  _Requirements: 7.3, 7.4, 9.1_ _Design: §2.1, §2.2_
- [ ] 6.2 Set CRUD + item add/reorder/remove (drag or position param), inline one-off text
  slides (`reusable=false, set_id=set`). System test: build a mixed Set (song + sermon slide),
  reorder, persist.
  _Requirements: 7.2, 7.3_ _Design: §5, §9_
- [ ] 6.3 Song search (`ILIKE`/`pg_trgm` over title/author/plain_text, church-scoped) +
  paginated alphabetical browse; text-slide search over title/subtype/body. System test:
  search by a lyric word returns the song.
  _Requirements: 8.1, 8.2, 8.3_ _Design: §8_

## 7. Live sync

- [ ] 7.1 Generate `LiveSession` (`set_id`, `status` check, `current_set_item_id`,
  `current_section_index`, `position_version bigint`, `lock_version`, `blanked`, `font_scale`,
  unique nullable tokens, timestamps). `POST sets/:id/launch` creates it, seeds position at the
  first `set_item`, generates tokens. Tests: launch seeds position; tokens unique.
  _Requirements: 6.1, 7.5_ _Design: §2.1, §6.1_
- [ ] 7.2 Operator view + advance/back/goto actions: walk sections (arrangement-aware,
  resolving replays) across items; each move bumps `position_version` and checks `lock_version`
  in one transaction; **broadcast inline** via `turbo_stream_from [session, role]`, frame
  carries version. Add a one-line capture **seam** in the position-change transaction for 8.1
  to hook (so usage capture is purely additive later). Tests: advance moves section then item;
  `position_version` monotonic; concurrent-operator `lock_version` conflict surfaces.
  _Requirements: 6.2, 6.5_ _Design: §6.1, §6.2_ _Depends: 4.4 (musician partial), 3.5 (transpose helper)_
- [ ] 7.3 Projector + musician public views via token-gated actions (`p/:token`, `m/:token`),
  subscribing with signed `turbo_stream_from`; bad/ended token → 404. Musician re-renders
  server-side at its own stored key/capo on each frame (independent per follower). System
  test: operator advance updates both followers; two musicians on different keys each see their
  own.
  _Requirements: 5.6, 6.3, 6.4, 6.6_ _Design: §3.2.4, §6.1, §6.3_ _Depends: 4.3 (projector partial), 4.4 (musician partial)_
- [ ] 7.4 Follower version guard (Stimulus): store last applied `position_version`, drop frames
  `<=` it; projector freezes on disconnect (no error/spinner) and re-syncs on reconnect; re-fit
  font on each stream render. System test: rapid advance never flashes backward; simulated
  disconnect holds last frame.
  _Requirements: 6.2, 6.7_ _Design: §6.2, §6.4_ _Depends: 4.3 (fit controller)_
- [ ] 7.5 Blank toggle + font ± actions: update `blanked`/`font_scale` on the session and
  broadcast to the projector (reusing the 4.3 `fit` controller). System test: blank blacks the
  projector; font ± rescales live.
  _Requirements: 6.8_ _Design: §6.1, §5_ _Depends: 4.3 (fit controller)_
- [ ] 7.6 Late-join / reload recovery: `operator#show` and the follower token GET both render
  the current item/section at the current `position_version` from the `LiveSession` row. System
  tests: a follower joining mid-service lands on the current slide; operator browser reload
  lands on current position.
  _Requirements: 6.4, 6.9, 6.11_ _Design: §6.4_
- [ ] 7.7 End session: status→ended, tokens nulled; follower streams render a neutral
  "service ended" state; tokens 404 thereafter. System test: ending revokes both tokens and
  shows the neutral state.
  _Requirements: 6.7 (end)_ _Design: §6.4_

## 8. CCLI compliance

- [ ] 8.1 Generate `UsageEvent` (church, live_session, song, snapshot ccli#/title/author/
  copyright_status, shown_at) with unique `(live_session_id, song_id)`. Hook the idempotent
  capture into the **7.2 position-change seam** (skip public-domain), passing `church`/
  `live_session` explicitly (never `Current` off-request). Tests: one event per song per
  session; public-domain skipped; snapshot immune to later song edit.
  _Requirements: 9.5_ _Design: §3.2.3, §7_ _Depends: 7.2 (capture seam)_
- [ ] 8.2 Usage report CSV export (`GET reports/usage`, admin/editor, church-scoped, date
  range, group by ccli#/title/author count, exclude public-domain). Test: CSV shape + scoping.
  _Requirements: 9.6_ _Design: §7, §9_
- [ ] 8.3 Confirm end-to-end that the copyright notice (built with full suppression in 4.3)
  composes the church `ccli_license_number` correctly in a live projection context. (Suppression
  logic and its "no wrong notice" test already live in 4.3.) Test: live projector shows the
  correct notice for a licensed copyrighted song.
  _Requirements: 9.4_ _Design: §5, §7_

## 9. Data migration (LAST)

- [ ] 9.1 Implement `Corobook::Legacy::ChordProConverter`: legacy column-aligned blob →
  ChordPro. Tab expansion, Unicode grapheme-column mapping, `//`→repeat/chorus directive,
  `[LABEL]`→section label, legacy `order`→`arrangement`, malformed-token tolerance. Unit tests
  on representative legacy snippets (tabs, accented caps, combining-ring `C°`).
  _Requirements: 2.8_ _Design: §4.5_
- [ ] 9.2 Implement an idempotent, re-runnable reader for the dump at
  `/Users/blablo/Development/corobook/songs.sql` → in-memory legacy song/user records. Unit
  test on a small fixture subset of the dump.
  _Requirements: 11.1, 11.5_ _Design: §4.5_
- [ ] 9.3 Round-trip **gate** over the full dump: for each song convert → parse → assert
  round-trip; emit a per-song pass/fail report; **write ZERO rows if any song fails**. Run
  against the real dump and confirm the report. This is the migration's safety gate and must
  be green before 9.4.
  _Requirements: 11.2_ _Design: §4.3a, §4.5_
- [ ] 9.4 Actual import (only after 9.3 is green): import songs into the designated church with
  `copyright_status=unknown`; map legacy users to a church with admin/editor roles; idempotent
  re-run. Verify counts against the dump; report per-song outcome.
  _Requirements: 11.1, 11.3, 11.4, 11.6_ _Design: §4.5, §7_ _Depends: 9.3 (round-trip gate)_

## 10. Final verification

- [ ] 10.1 Full-suite green: `bin/rails test` + `bin/rails test:system`. End-to-end system
  test of the headline flow — author songs + a mixed Set, launch, drive the service, projector
  + two differently-keyed musicians follow, blank, reload recovery, copyright notice, usage
  recorded, CSV exported. Confirm no cross-church leakage anywhere.
  _Requirements: all_ _Design: §10_
