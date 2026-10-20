# Legacy song migration: pull the old corobook MySQL `songs` into this app's Song records,
# converting the column-aligned chord/lyric blob to ChordPro via Corobook::Legacy::ChordProConverter.
#
# Two decoupled steps so a production pull is reproducible and reviewable offline:
#
#   1. Extract  → a JSON fixture (reads the legacy MySQL, read-only). The old server speaks the
#      legacy mysql_native_password plugin that the MySQL 9 client dropped, so use a MySQL 8
#      client (e.g. via Docker). A ready script lives at scripts/extract_legacy_songs.sh:
#        LEGACY_DB_HOST=... LEGACY_DB_PASSWORD=... OUT=tmp/legacy_songs.json \
#          scripts/extract_legacy_songs.sh
#
#   2. Import   → create Song rows in a target church (idempotent on church+title):
#        CHURCH_ID=1 [IN=tmp/legacy_songs.json] [DRY_RUN=1] [UPDATE=1] \
#          bin/rails corobook:import_legacy_songs
#
# Extract touches production (read-only); import touches only this app's DB and the JSON fixture.
# Keep the fixture out of git if it carries real lyric data (tmp/ is gitignored).

namespace :corobook do
  desc "Import legacy songs from a JSON fixture into a target church (idempotent on church+title)"
  task import_legacy_songs: :environment do
    require "json"

    church_id = ENV.fetch("CHURCH_ID")
    church = Church.find(church_id)
    path = ENV.fetch("IN", "tmp/legacy_songs.json")
    dry_run = ENV["DRY_RUN"].present?
    update_existing = ENV["UPDATE"].present?

    rows = JSON.parse(File.read(path), symbolize_names: true)
    created = 0
    updated = 0
    skipped = 0
    failed = []

    rows.each do |row|
      title = row[:title].to_s.strip
      if title.empty?
        failed << { id: row[:id], error: "blank title" }
        next
      end

      converter = Corobook::Legacy::ChordProConverter.new(row[:lyric], order: row[:order], mood: row[:mood])
      attrs = {
        title: title,
        author: row[:author].presence,
        chordpro_source: converter.convert,
        arrangement: converter.arrangement,
        link: row[:link].presence,
        reference: row[:reference].presence
      }

      existing = church.songs.find_by(title: title)
      if existing
        if update_existing
          existing.update!(attrs) unless dry_run
          updated += 1
        else
          skipped += 1
        end
      else
        church.songs.create!(attrs) unless dry_run
        created += 1
      end
    rescue => e
      failed << { id: row[:id], title: row[:title], error: e.message }
    end

    puts "#{dry_run ? '[DRY RUN] ' : ''}church ##{church.id} (#{church.name}): " \
         "#{created} created, #{updated} updated, #{skipped} skipped (existing), #{failed.length} failed"
    failed.first(20).each { |f| puts "  FAILED ##{f[:id]} #{f[:title]}: #{f[:error]}" }
  end
end
