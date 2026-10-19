class Song < ApplicationRecord
  include ChurchChild

  enum :copyright_status,
    { copyrighted: "copyrighted", public_domain: "public_domain", unknown: "unknown" },
    validate: true

  validates :title, presence: true
  validates :capo, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 11 }

  before_save :derive_parsed_lyric

  # Case-insensitive search over title, author, and derived lyric text. Backed by the pg_trgm
  # GIN index on plain_text (§8); ILIKE lets the trigram index serve partial matches.
  scope :search, ->(q) {
    next all if q.blank?

    pattern = "%#{sanitize_sql_like(q.to_s.strip)}%"
    where("title ILIKE :p OR author ILIKE :p OR plain_text ILIKE :p", p: pattern)
  }

  # The ParsedLyric for views, built lazily from the stored JSONB.
  def parsed
    Corobook::ChordPro::ParsedLyric.from_hash(parsed_lyric || {})
  end

  private

  # Parse the ChordPro source into the stored JSONB + searchable plain text on every save. The
  # parser never raises, so a malformed chord is captured verbatim and never blocks a save.
  def derive_parsed_lyric
    parsed = Corobook::ChordPro::Parser.parse(chordpro_source.to_s)
    self.parsed_lyric = parsed.to_h
    self.plain_text = Corobook::ChordPro::Transform.plain_text(parsed)
  end
end
