# frozen_string_literal: true

require "timeout"

module Corobook
  # Turns an uploaded PDF (typically a Google Slides / PowerPoint / Keynote export) into one
  # reusable, imported TextSlide whose pages are rendered images, so a deck plays on the
  # projector with the normal Next/Back stops.
  #
  # Built for a small server:
  # * the upload is streamed to disk, never read whole into memory;
  # * only ONE conversion runs at a time across all app processes (a Postgres advisory lock);
  #   a second import is told to try again rather than competing for CPU and memory;
  # * `pdftoppm` runs at low CPU priority (nice), without a shell, with a time limit, and is
  #   capped at MAX_PAGES + 1 pages so an oversized file cannot render thousands of pages.
  #
  # Office files (.pptx, .key, .odp...) are not converted on the server: that needs LibreOffice,
  # which is too heavy here. They get a message asking for a PDF export instead.
  class PdfSlideImporter
    class Error < StandardError
      attr_reader :key

      def initialize(key)
        @key = key
        super(key.to_s)
      end
    end

    MAX_BYTES = 30.megabytes
    MAX_PAGES = 60
    RENDER_WIDTH = 1920 # matches a 1080p projector
    JPEG_QUALITY = 85
    TIMEOUT_SECONDS = 120
    LOCK_KEY = 0x636f726f # "coro": app-wide key for the one-conversion-at-a-time lock

    OFFICE_EXTENSIONS = %w[.pptx .ppt .pps .ppsx .key .odp].freeze
    ZIP_MAGIC = "PK\x03\x04".b
    OLE_MAGIC = "\xD0\xCF\x11\xE0".b # legacy .ppt

    # Renders `pdf_path` into `out_dir`, returning the image paths in page order. Swappable in tests.
    class_attribute :rasterizer, default: lambda { |pdf_path, out_dir|
      prefix = File.join(out_dir, "page")
      PdfSlideImporter.run!("nice", "-n", "10",
                            "pdftoppm", "-jpeg", "-jpegopt", "quality=#{JPEG_QUALITY}",
                            "-scale-to-x", RENDER_WIDTH.to_s, "-scale-to-y", "-1",
                            "-l", (MAX_PAGES + 1).to_s, pdf_path, prefix)
      Dir.glob("#{prefix}-*.jpg").sort_by { |f| f[/-(\d+)\.jpg\z/, 1].to_i }
    }

    def self.call(...) = new(...).call

    def initialize(church:, file:, title:)
      @church = church
      @file = file
      @title = title.to_s.strip
    end

    def call
      raise Error, :missing_file if @file.blank?
      raise Error, :too_large if @file.size > MAX_BYTES

      head = file_head
      raise Error, :office_file if office_file?(head)
      raise Error, :not_pdf unless head.start_with?("%PDF-")

      with_conversion_lock do
        Dir.mktmpdir("corobook-pdf") do |dir|
          pdf_path = File.join(dir, "deck.pdf")
          copy_upload_to(pdf_path)
          images = rasterizer.call(pdf_path, dir)
          raise Error, :no_pages if images.empty?
          raise Error, :too_many_pages if images.size > MAX_PAGES

          save_slide(images)
        end
      end
    end

    # True when `name` is an executable on PATH.
    def self.executable?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
    end

    # Runs a command without a shell; raises Error(:unreadable) on failure or timeout.
    # The real converter is checked up front: it runs under `nice`, which would otherwise turn a
    # missing pdftoppm into exit 127 and a misleading "couldn't read that PDF".
    def self.run!(*cmd)
      converter = cmd.first == "nice" ? cmd[3] : cmd.first
      raise Error, :converter_missing unless executable?(converter)

      pid = Process.spawn(*cmd, out: File::NULL, err: File::NULL)
      status = Timeout.timeout(TIMEOUT_SECONDS) { Process.wait2(pid).last }
      raise Error, :converter_missing if status.exitstatus == 127
      raise Error, :unreadable unless status.success?
    rescue Timeout::Error
      Process.kill("KILL", pid)
      Process.wait(pid)
      raise Error, :unreadable
    rescue Errno::ENOENT
      raise Error, :converter_missing
    end

    private

    def upload_io = @file.respond_to?(:tempfile) ? @file.tempfile : @file

    # First bytes of the upload. Trust these, not the file name or the browser's content type.
    def file_head
      io = upload_io
      io.rewind
      (io.read(8) || "").b.tap { io.rewind }
    end

    # PowerPoint / Keynote / Impress decks: by name, or by an Office container signature.
    def office_file?(head)
      ext = File.extname(@file.original_filename.to_s).downcase
      OFFICE_EXTENSIONS.include?(ext) || head.start_with?(ZIP_MAGIC) || head.start_with?(OLE_MAGIC)
    end

    # Stream the upload to disk in chunks (no full copy in memory).
    def copy_upload_to(path)
      io = upload_io
      io.rewind
      File.open(path, "wb") { |out| IO.copy_stream(io, out) }
    end

    # One conversion at a time, server-wide. Session-level advisory lock on this request's
    # connection; released in ensure even if the conversion fails.
    def with_conversion_lock
      conn = ActiveRecord::Base.connection
      raise Error, :busy unless conn.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")

      begin
        yield
      ensure
        conn.select_value("SELECT pg_advisory_unlock(#{LOCK_KEY})")
      end
    end

    def save_slide(images)
      title = @title.presence || File.basename(@file.original_filename.to_s, ".*").presence || "Imported slides"
      slide = @church.text_slides.build(title: title, reusable: true, imported: true,
                                        pages: images.map { { "body_markdown" => "" } })
      files = images.map { |path| File.open(path, "rb") }
      files.each_with_index do |f, i|
        slide.page_images.attach(io: f, filename: "page-#{i + 1}.jpg", content_type: "image/jpeg")
      end
      slide.save!
      slide
    ensure
      files&.each(&:close)
    end
  end
end
