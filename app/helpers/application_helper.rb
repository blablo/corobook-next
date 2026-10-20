module ApplicationHelper
  # Inline SVG QR code for a URL (no external request — scannable offline on the projector).
  # `size` is the rendered pixel size; the SVG scales crisply to it.
  def qr_svg(url, size: 160)
    qr = RQRCode::QRCode.new(url.to_s)
    raw qr.as_svg(
      module_size: 4, standalone: true, use_path: true,
      viewbox: true, svg_attributes: {
        width: size, height: size, role: "img",
        aria: { label: "QR code for #{url}" }, class: "rounded bg-white p-1"
      }
    )
  end
end
