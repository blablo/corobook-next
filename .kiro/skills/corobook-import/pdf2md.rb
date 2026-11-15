# Rebuild slide pages from pdftohtml -xml: paragraphs as typed in PowerPoint/Keynote (lines the
# text box only wrapped for width are joined back; real line breaks are kept), italic/bold runs, a
# same-size heading line, verse superscripts (as Unicode superscripts) and the reference line.
require "nokogiri"
SUP = { "0"=>"⁰","1"=>"¹","2"=>"²","3"=>"³","4"=>"⁴","5"=>"⁵","6"=>"⁶","7"=>"⁷","8"=>"⁸","9"=>"⁹" }
LIG = { "af icted"=>"afflicted", "af iction"=>"affliction", "justi ed"=>"justified", "cruci ed"=>"crucified",
        "glori ed"=>"glorified", "sacri ce"=>"sacrifice" }

def page_md(pdf, page)
  xml = `pdftohtml -xml -i -q -stdout -f #{page} -l #{page} #{pdf}`
  doc = Nokogiri::XML(xml)
  sizes = doc.css("fontspec").to_h { |f| [f["id"], f["size"].to_i] }
  body = sizes.values.max
  items = doc.css("text").map do |t|
    txt = t.text.tr("\u00A0", " ")
    next if txt.strip.empty? || txt.strip =~ /\A(fi|fl)\z/
    sz = sizes[t["font"]]
    { top: t["top"].to_i, left: t["left"].to_i, w: t["width"].to_i, h: t["height"].to_i, size: sz, text: txt,
      i: !t.at_css("i").nil?, b: !t.at_css("b").nil? }
  end.compact
  # Superscript verse numbers: smaller than body, digits only.
  items.each { |it| it[:sup] = it[:text].strip =~ /\A\d+\z/ && it[:size] < body * 0.8 }
  # Group into lines by vertical position (superscripts sit a little higher than their line).
  lines = []
  items.sort_by { |it| [it[:top], it[:left]] }.each do |it|
    line = lines.find { |l| (l[:top] - it[:top]).abs < [it[:h], l[:items].map { |x| x[:h] }.max].min * 0.5 && (it[:sup] || l[:items].all? { |x| x[:sup] || (x[:size] < body * 0.6) == (it[:size] < body * 0.6) }) }
    line ? line[:items] << it : lines << { top: it[:top], items: [it] }
  end
  lines.sort_by! { |l| l[:top] }

  # Each PDF line -> its styled segments plus geometry for the wrap test.
  rows = lines.map do |l|
    runs = l[:items].sort_by { |it| it[:left] }
    small = runs.all? { |r| r[:size] < body * 0.6 && !r[:sup] }
    words = runs.reject { |r| r[:sup] }
    chars = words.sum { |r| r[:text].length }
    first = words.first ? words.first[:text].strip[/\S+/].to_s : ""
    { segs: line_segs(runs), small: small, top: l[:top], bottom: l[:top] + runs.map { |r| r[:h] }.max,
      left: runs.first[:left], right: runs.map { |r| r[:left] + r[:w] }.max,
      charw: chars.positive? ? words.sum { |r| r[:w] }.to_f / chars : 0,
      first_word_w: chars.positive? ? words.sum { |r| r[:w] }.to_f / chars * (first.length + 1) : 0 }
  end
  # The text box's right edge, per left margin (deck_right): a slide whose lines are all short
  # never reaches it, so its own widest line would wrongly look full. A line is only joined to one
  # that starts at the same margin (centred or indented lines don't share a right edge).
  body_rows = rows.reject { |r| r[:small] }
  small_right = rows.select { |r| r[:small] }.map { |r| r[:right] }.max
  edge_for = lambda do |row|
    return small_right if row[:small]

    same = body_rows.select { |r| (r[:left] - row[:left]).abs < 40 }
    deck_right(pdf, row[:left], body, same.map { |r| r[:right] }.max)
  end

  # Join a line onto the one above when the text box wrapped it: the first word of this line would
  # not have fit at the end of the line above. Anything else is a line break the author typed.
  paras = []
  rows.each_with_index do |row, i|
    prev = i.positive? ? rows[i - 1] : nil
    gap = prev && (row[:top] - prev[:bottom]) > body * 0.9 && !(row[:small] && prev[:small])
    same_margin = prev && (prev[:left] - row[:left]).abs < 40
    edge = same_margin && prev[:small] == row[:small] ? edge_for.call(prev) : nil
    # Half a character of slack: pdftohtml widths include a trailing space on some runs only.
    wrapped = prev && !gap && edge && prev[:right] + row[:first_word_w] > edge - prev[:charw] / 2
    if wrapped
      paras.last[:segs] = join_segs(paras.last[:segs], row[:segs])
    else
      paras << { segs: row[:segs], small: row[:small], gap: gap }
    end
  end

  out = []
  prev_small = false
  paras.each do |para|
    text = render_segs(para[:segs])
    LIG.each { |k, v| text = text.gsub(k, v) }
    out << "" if para[:gap] || para[:small] && !prev_small && out.any? && out.last != ""
    # Lines set much smaller than the body (references, footnotes) become Corobook small text.
    out << (para[:small] && !text.empty? ? "~#{text.gsub('~', '\\~')}~" : text)
    prev_small = para[:small]
  end
  out.join("\n").gsub(/\n{3,}/, "\n\n").strip
end

# The right edge of the text box for a line on this page: the page's own widest line at that
# margin, or the deck's usual edge (75th percentile of each page's widest line at this body size)
# when this page's lines are all short. Keynote/PowerPoint layouts mostly reuse one box, but some
# slides widen it, so the page's own widest line wins when it reaches further. `left` is unused
# beyond documenting the caller's margin.
def deck_right(pdf, left, body, page_max)
  @deck_pages ||= {}
  @deck_pages[pdf] ||= begin
    doc = Nokogiri::XML(`pdftohtml -xml -i -q -stdout #{pdf}`)
    sizes = doc.css("fontspec").to_h { |f| [f["id"], f["size"].to_i] }
    doc.css("page").filter_map do |pg|
      texts = pg.css("text").select { |t| t.text.strip.length > 3 }
      next if texts.empty?

      pbody = texts.map { |t| sizes[t["font"]].to_i }.max
      rows = texts.select { |t| sizes[t["font"]].to_i >= pbody * 0.6 }
      rows.empty? ? nil : { body: pbody, lines: rows.map { |t| [t["left"].to_i, t["left"].to_i + t["width"].to_i] } }
    end
  end
  maxima = @deck_pages[pdf].filter_map do |pg|
    next unless (pg[:body] - body).abs <= 2

    pg[:lines].map(&:last).max
  end.sort
  usual = maxima.empty? ? page_max : maxima[(maxima.size * 0.75).floor.clamp(0, maxima.size - 1)]
  [page_max.to_i, usual.to_i].max
end

# Merge consecutive runs of the same style into [style, text] segments. Tiny non-word runs
# (ª º *) stay plain; superscript digits become Unicode superscripts.
def line_segs(runs)
  segs = []
  runs.each do |r|
    raw = r[:text].gsub("*", "\\*")
    if r[:sup]
      segs << [nil, " " + r[:text].strip.chars.map { |c| SUP[c] }.join + " "]
      next
    end
    style = r[:i] && r[:b] ? "***" : r[:i] ? "*" : r[:b] ? "**" : ""
    style = nil if raw.strip.empty? || raw.strip.gsub("\\", "") !~ /[[:alnum:]]{2}/
    if segs.any? && (segs.last[0] == style || style.nil? && raw.strip.empty?)
      segs.last[1] << raw
    else
      segs << [style, raw.dup]
    end
  end
  segs
end

# Two wrapped lines -> one: a space between, and one segment where the style carries on.
def join_segs(a, b)
  a = a.map(&:dup)
  b = b.map(&:dup)
  return a + b if a.empty? || b.empty?

  if a.last[0] == b.first[0]
    a.last[1] = a.last[1].rstrip + " " + b.first[1].lstrip
    a + b.drop(1)
  else
    a.last[1] = a.last[1].rstrip + " "
    a + b
  end
end

# Segments -> markdown, whitespace kept outside the markers so CommonMark emphasis parses.
def render_segs(segs)
  segs.map do |style, t|
    next t if style.nil? || style.empty?
    core = t.strip
    next t if core.empty?
    "#{t[/\A\s*/]}#{style}#{core}#{style}#{t[/\s*\z/]}"
  end.join.squeeze(" ").strip
end

def page_layout(pdf, page)
  doc = Nokogiri::XML(`pdftohtml -xml -i -q -stdout -f #{page} -l #{page} #{pdf}`)
  sizes = doc.css("fontspec").to_h { |f| [f["id"], f["size"].to_i] }
  body = sizes.values.max
  w = doc.at_css("page")["width"].to_f
  tx = doc.css("text").select { |t| sizes[t["font"]] == body && t.text.strip.length > 3 }
  lefts = tx.map { |t| t["left"].to_i }
  centers = tx.map { |t| t["left"].to_i + t["width"].to_i / 2.0 }
  align = (lefts.max - lefts.min) < w * 0.03 ? "left" : (centers.all? { |c| (c - w / 2).abs < w * 0.03 } ? "center" : "left")
  tops = doc.css("text").map { |t| t["top"].to_i }
  valign = tops.min < doc.at_css("page")["height"].to_f * 0.1 ? "top" : "center"
  # pdftohtml zoom is 1.5 and the page is 1080 pt tall; Corobook's canvas is 540 pt.
  pt = body / 1.5 * 540 / doc.at_css("page")["height"].to_f * 1.5
  # The body text's colour (most common among body-size runs), for the slide's text_color.
  colors = doc.css("fontspec").to_h { |f| [f["id"], f["color"]] }
  color = tx.map { |t| colors[t["font"]] }.compact.tally.max_by { |_, n| n }&.first
  ratio, spacing = line_spacing(tx, body)
  { size_pt: pt.round, align: align, valign: valign, text_color: color, line_ratio: ratio, line_height: spacing }
end

# Line spacing as Corobook stores it: the distance from one line to the next as a multiple of the
# font size (CSS line-height), the nearest of LINE_HEIGHTS. Measured from the tops of consecutive
# body lines; gaps over 1.8x the size are paragraph breaks and are skipped. Returns [ratio, value],
# value nil when it rounds to the default (so the slide keeps its default spacing) or when the
# page has fewer than two lines.
LINE_HEIGHTS = { "1.0" => 1.0, "1.15" => 1.15, "1.5" => 1.5, "2.0" => 2.0 }.freeze
DEFAULT_LINE_HEIGHT = "1.15"

def line_spacing(body_runs, body)
  tops = body_runs.map { |t| t["top"].to_i }.uniq.sort
  steps = tops.each_cons(2).map { |a, b| b - a }.select { |d| d.positive? && d < body * 1.8 }
  return [nil, nil] if steps.empty?

  ratio = (steps.sort[steps.size / 2].to_f / body).round(2)
  value = LINE_HEIGHTS.min_by { |_, v| (v - ratio).abs }.first
  [ratio, value == DEFAULT_LINE_HEIGHT ? nil : value]
end

if __FILE__ == $0
  ARGV[1..].each { |p| puts "=== p#{p}"; puts page_md(ARGV[0], p) }
end
