# Rebuild slide pages from pdftohtml -xml: keeps the PDF's line breaks, italic/bold runs,
# a same-size heading line, verse superscripts (as Unicode superscripts) and the reference line.
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
    { top: t["top"].to_i, left: t["left"].to_i, h: t["height"].to_i, size: sz, text: txt,
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
  out = []
  prev_bottom = nil
  prev_small = false
  lines.each do |l|
    runs = l[:items].sort_by { |it| it[:left] }
    small = runs.all? { |r| r[:size] < body * 0.6 && !r[:sup] }
    # Merge consecutive runs of the same style, then wrap each segment (whitespace kept outside
    # the markers so CommonMark emphasis parses). Tiny non-word runs (ª º *) stay plain.
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
        segs << [style, raw]
      end
    end
    text = segs.map do |style, t|
      next t if style.nil? || style.empty?
      core = t.strip
      next t if core.empty?
      "#{t[/\A\s*/]}#{style}#{core}#{style}#{t[/\s*\z/]}"
    end.join.squeeze(" ").strip
    LIG.each { |k, v| text = text.gsub(k, v) }
    gap = prev_bottom && (l[:top] - prev_bottom) > body * 0.9 && !(small && prev_small)
    out << "" if gap || small && !prev_small && out.any? && out.last != ""
    out << text
    prev_bottom = l[:top] + l[:items].map { |r| r[:h] }.max
    prev_small = small
  end
  out.join("\n").gsub(/\n{3,}/, "\n\n").strip
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
  { size_pt: pt.round, align: align, valign: valign }
end

if __FILE__ == $0
  ARGV[1..].each { |p| puts "=== p#{p}"; puts page_md(ARGV[0], p) }
end
