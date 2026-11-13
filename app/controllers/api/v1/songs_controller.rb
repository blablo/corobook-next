module Api
  module V1
    class SongsController < BaseController
      # GET /api/v1/songs?q=  — find existing songs (duplicate check before creating).
      def index
        songs = church.songs.search(params[:q]).order(:title).limit(50)
        render json: { songs: songs.map { |s| summary(s) } }
      end

      # POST /api/v1/songs  { song: {...}, dry_run: true|false }
      # Duplicate = same title (case-insensitive) in this church -> 409 with the existing id.
      def create
        song = church.songs.build(song_params)
        existing = church.songs.where("lower(title) = ?", song.title.to_s.strip.downcase).first
        return render json: { error: "duplicate", existing: summary(existing) }, status: :conflict if existing && song.title.present?
        return render json: { error: "invalid", messages: song.errors.full_messages }, status: :unprocessable_entity unless song.valid?
        return render json: { dry_run: true, would_create: summary(song).merge(chordpro_source: song.chordpro_source) } if dry_run?

        song.save!
        render json: { song: summary(song) }, status: :created
      end

      # GET /api/v1/songs/:id  — full content, to read before an update.
      def show
        render json: { song: detail(church.songs.find(params[:id])) }
      end

      # PATCH /api/v1/songs/:id  { song: {only the fields to change}, dry_run: true|false }
      # Partial: omitted fields are kept. Renaming onto another song's title -> 409.
      def update
        song = church.songs.find(params[:id])
        song.assign_attributes(song_params)
        changes = song.changes.except("updated_at")
        clash = song.title_changed? && church.songs.where.not(id: song.id).where("lower(title) = ?", song.title.to_s.strip.downcase).first
        return render json: { error: "duplicate", existing: summary(clash) }, status: :conflict if clash
        return render json: { error: "invalid", messages: song.errors.full_messages }, status: :unprocessable_entity unless song.valid?
        return render json: { dry_run: true, would_change: changes.keys, would_update: detail(song) } if dry_run?

        song.save!
        render json: { song: detail(song), changed: changes.keys }
      end

      private

      def summary(song)
        { id: song.id, title: song.title, author: song.author, song_key: song.song_key, url: song.persisted? ? Rails.application.routes.url_helpers.song_url(song, host: host) : nil }
      end

      def detail(song)
        summary(song).merge(song.slice(:subtitle, :reference, :link, :capo, :copyright_line, :ccli_song_number,
                                       :copyright_status, :chordpro_source, :arrangement).symbolize_keys)
      end

      def host = ENV["APP_HOST"].presence || request.host_with_port

      def song_params
        permitted = params.require(:song).permit(
          :title, :author, :subtitle, :reference, :link, :song_key, :capo,
          :copyright_line, :ccli_song_number, :copyright_status, :chordpro_source, arrangement: []
        )
        permitted[:copyright_status] ||= "unknown" if action_name == "create"
        permitted
      end
    end
  end
end
