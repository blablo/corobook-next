require "csv"

class ReportsController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_admin

  # CCLI usage report (§7, Req 9.6): one row per distinct song over a date range, with a play
  # count, church-scoped, excluding public-domain songs (nothing to report for those).
  def usage
    from = parse_date(params[:from]) || 1.month.ago.to_date
    to = parse_date(params[:to]) || Date.current

    rows = church_scope(:usage_events)
      .where(shown_at: from.beginning_of_day..to.end_of_day)
      .where.not(copyright_status: "public_domain")
      .group(:ccli_song_number, :title, :author)
      .count

    csv = CSV.generate do |out|
      out << [ "CCLI Song Number", "Title", "Author", "Times Used" ]
      rows.sort_by { |(_ccli, title, _author), _count| title.to_s }.each do |(ccli, title, author), count|
        out << [ ccli, title, author, count ]
      end
    end

    send_data csv, filename: "ccli-usage-#{from}-to-#{to}.csv", type: "text/csv"
  end

  private

  def parse_date(value)
    Date.parse(value) if value.present?
  rescue ArgumentError
    nil
  end
end
