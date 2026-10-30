require "test_helper"

class PdfSlideImporterTest < ActiveSupport::TestCase
  Importer = Corobook::PdfSlideImporter

  setup do
    @church = Church.create!(name: "Central")
    @original_rasterizer = Importer.rasterizer
  end

  teardown { Importer.rasterizer = @original_rasterizer }

  def pdf_upload(name = "two_pages.pdf")
    Rack::Test::UploadedFile.new(file_fixture(name), "application/pdf")
  end

  # Stand-in renderer: writes `count` small images, like pdftoppm would.
  def fake_pages(count)
    Importer.rasterizer = lambda do |_pdf, dir|
      (1..count).map do |i|
        path = File.join(dir, "page-#{i}.jpg")
        FileUtils.cp(file_fixture("bg.png"), path)
        path
      end
    end
  end

  test "creates a reusable imported slide with one image page per PDF page" do
    fake_pages(3)
    slide = Importer.call(church: @church, file: pdf_upload, title: "Anuncios")

    assert slide.persisted?
    assert slide.imported?
    assert slide.reusable?
    assert_equal "Anuncios", slide.title
    assert_equal 3, slide.page_count
    assert_equal 3, slide.page_images.count
    assert_equal "page-2.jpg", slide.page_image(1).filename.to_s
  end

  test "uses the file name when no title is given" do
    fake_pages(1)
    assert_equal "two_pages", Importer.call(church: @church, file: pdf_upload, title: "").title
  end

  test "rejects a file that is not a PDF, whatever its name or type" do
    fake = Rack::Test::UploadedFile.new(file_fixture("bg.png"), "application/pdf", original_filename: "deck.pdf")
    error = assert_raises(Importer::Error) { Importer.call(church: @church, file: fake, title: "x") }
    assert_equal :not_pdf, error.key
    assert_equal 0, @church.text_slides.count
  end

  test "asks for a PDF export when given a PowerPoint or Keynote file" do
    by_name = Rack::Test::UploadedFile.new(StringIO.new("anything"), "application/octet-stream", original_filename: "deck.pptx")
    by_bytes = Rack::Test::UploadedFile.new(StringIO.new("PK\x03\x04rest-of-zip".b), "application/pdf", original_filename: "deck.pdf")
    keynote = Rack::Test::UploadedFile.new(StringIO.new("PK\x03\x04".b), "application/octet-stream", original_filename: "talk.key")

    [ by_name, by_bytes, keynote ].each do |file|
      assert_equal :office_file, assert_raises(Importer::Error) { Importer.call(church: @church, file: file, title: "x") }.key
    end
    assert_equal 0, @church.text_slides.count
  end

  test "only one conversion runs at a time" do
    fake_pages(1)
    # A separate database session (another app process importing). The test's pooled
    # connections share one session, and advisory locks are re-entrant within a session.
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database],
                       user: cfg[:username], password: cfg[:password])
    other.exec("SELECT pg_advisory_lock(#{Importer::LOCK_KEY})")

    error = assert_raises(Importer::Error) { Importer.call(church: @church, file: pdf_upload, title: "x") }
    assert_equal :busy, error.key
  ensure
    other&.close # closing the session releases its lock
  end

  test "the lock is released after an import, even a failed one" do
    fake_pages(Importer::MAX_PAGES + 1)
    assert_raises(Importer::Error) { Importer.call(church: @church, file: pdf_upload, title: "x") }

    fake_pages(1)
    assert Importer.call(church: @church, file: pdf_upload, title: "ok").persisted?
  end

  test "renders at low priority with the projector-sized settings" do
    calls = []
    original = Importer.method(:run!)
    Importer.define_singleton_method(:run!) { |*cmd| calls << cmd }
    begin
      Dir.mktmpdir { |dir| @original_rasterizer.call(File.join(dir, "deck.pdf"), dir) }
    ensure
      Importer.define_singleton_method(:run!, original)
    end
    cmd = calls.first
    assert_equal %w[nice -n 10 pdftoppm], cmd.first(4)
    assert_includes cmd, "quality=#{Importer::JPEG_QUALITY}"
    assert_equal (Importer::MAX_PAGES + 1).to_s, cmd[cmd.index("-l") + 1]
  end

  test "a missing pdftoppm is reported as the converter missing, not an unreadable PDF" do
    original_path = ENV["PATH"]
    ENV["PATH"] = Dir.mktmpdir # nothing executable here
    error = assert_raises(Importer::Error) { Importer.run!("nice", "-n", "10", "pdftoppm", "-v") }
    assert_equal :converter_missing, error.key
  ensure
    ENV["PATH"] = original_path
  end

  test "rejects a missing file and too many pages" do
    assert_equal :missing_file, assert_raises(Importer::Error) { Importer.call(church: @church, file: nil, title: "x") }.key

    fake_pages(Importer::MAX_PAGES + 1)
    error = assert_raises(Importer::Error) { Importer.call(church: @church, file: pdf_upload, title: "x") }
    assert_equal :too_many_pages, error.key
    assert_equal 0, @church.text_slides.count
  end

  test "renders a real PDF with pdftoppm" do
    skip "pdftoppm (poppler-utils) not installed" unless system("which pdftoppm > /dev/null 2>&1")

    slide = Importer.call(church: @church, file: pdf_upload, title: "Real")
    assert_equal 2, slide.page_count
    assert_equal %w[image/jpeg image/jpeg], slide.page_images.map(&:content_type)
  end
end
