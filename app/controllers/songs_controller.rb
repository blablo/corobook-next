class SongsController < ApplicationController
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show]
  before_action :set_song, only: %i[show edit update destroy]

  def index
    @songs = church_scope(:songs).order(:title)
  end

  def show; end

  def new
    @song = church_scope(:songs).build(copyright_status: "unknown")
  end

  def edit; end

  def create
    @song = church_scope(:songs).build(song_params)
    if @song.save
      redirect_to @song, notice: "Song created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @song.update(song_params)
      redirect_to @song, notice: "Song updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @song.destroy
    redirect_to songs_path, notice: "Song deleted."
  end

  private

  def set_song
    @song = find_in_church(:songs, params[:id])
  end

  def song_params
    permitted = params.require(:song).permit(
      :title, :author, :subtitle, :reference, :link, :song_key, :capo,
      :copyright_line, :ccli_song_number, :copyright_status, :chordpro_source, :arrangement_text
    )
    arrangement_text = permitted.delete(:arrangement_text)
    permitted[:arrangement] = parse_arrangement(arrangement_text) if arrangement_text
    permitted
  end

  # The arrangement editor is a newline/comma-separated list of section labels; empty means
  # render in section order (stored as nil).
  def parse_arrangement(text)
    labels = text.to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)
    labels.empty? ? nil : labels
  end
end
