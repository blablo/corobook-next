#!/usr/bin/env bash
# Extract the legacy corobook `songs` table to a JSON fixture (read-only).
#
# The old server is MySQL 5.x (no JSON_ARRAYAGG) and uses the mysql_native_password auth plugin
# the MySQL 9 client dropped — so this uses a MySQL 8 client via Docker and a --batch TSV dump,
# which mysql emits with tabs/newlines backslash-escaped. A tiny Ruby pass turns that into JSON.
# Creds come from the environment, never hardcoded.
#
#   LEGACY_DB_HOST=1.2.3.4 LEGACY_DB_PASSWORD='***' \
#     [LEGACY_DB_USER=root] [LEGACY_DB_NAME=corobook_production] [OUT=tmp/legacy_songs.json] \
#     scripts/extract_legacy_songs.sh
set -euo pipefail

: "${LEGACY_DB_HOST:?set LEGACY_DB_HOST}"
: "${LEGACY_DB_PASSWORD:?set LEGACY_DB_PASSWORD}"
USER="${LEGACY_DB_USER:-root}"
DB="${LEGACY_DB_NAME:-corobook_production}"
OUT="${OUT:-tmp/legacy_songs.json}"
TSV="$(mktemp)"
trap 'rm -f "$TSV"' EXIT

mkdir -p "$(dirname "$OUT")"

# --batch gives tab-separated rows with \t, \n, \\ backslash-escaped inside field values.
docker run --rm -e MYSQL_PWD="$LEGACY_DB_PASSWORD" mysql:8 \
  mysql -h "$LEGACY_DB_HOST" -u "$USER" --connect-timeout=20 --default-character-set=utf8mb4 \
        --batch -e \
  "SELECT id, title, author, lyric, link, reference, mood, \`order\` FROM songs ORDER BY id;" \
  "$DB" > "$TSV"

# Parse the batch TSV (header row + escaped fields) into JSON.
ruby -rjson -e '
  raw = File.binread(ARGV[0]).force_encoding("UTF-8").scrub("")
  lines = raw.split("\n", -1)
  headers = lines.shift.to_s.split("\t")
  unesc = ->(s) { s.gsub(/\\(.)/) { $1 == "n" ? "\n" : ($1 == "t" ? "\t" : $1) } }
  rows = lines.reject(&:empty?).map { |l|
    vals = l.split("\t", -1).map { |v| v == "NULL" ? nil : unesc.call(v) }
    h = headers.zip(vals).to_h
    h["id"] = h["id"]&.to_i; h["mood"] = h["mood"]&.to_i
    h
  }
  File.write(ARGV[1], JSON.pretty_generate(rows))
  puts "Extracted #{rows.length} songs → #{ARGV[1]}"
' "$TSV" "$OUT"
