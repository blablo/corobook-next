class Song < ApplicationRecord
  include ChurchChild

  enum :copyright_status,
    { copyrighted: "copyrighted", public_domain: "public_domain", unknown: "unknown" },
    validate: true

  validates :title, presence: true
  validates :capo, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 11 }

  validate :section_labels_unique, if: :will_save_change_to_chordpro_source?

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

  # The show and the arrangement find sections by label, so two sections sharing one label
  # collapse into a single one and verses vanish. Replayed choruses ({chorus}) repeat on purpose.
  def section_labels_unique
    sections = Corobook::ChordPro::Parser.parse(chordpro_source.to_s).to_h["sections"].to_a
    labels = sections.reject { |s| s["replay_of"] }.filter_map { |s| s["label"].presence }
    dupes = labels.tally.select { |_, n| n > 1 }.keys
    return if dupes.empty?

    errors.add(:chordpro_source, "has more than one section labelled #{dupes.to_sentence}; give each section its own name")
  end

  # Parse the ChordPro source into the stored JSONB + searchable plain text on every save. The
  # parser never raises, so a malformed chord is captured verbatim and never blocks a save.
  def derive_parsed_lyric
    parsed = Corobook::ChordPro::Parser.parse(chordpro_source.to_s)
    self.parsed_lyric = parsed.to_h
    self.plain_text = Corobook::ChordPro::Transform.plain_text(parsed)
  end
end
