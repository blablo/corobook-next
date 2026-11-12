class MembersController < ApplicationController
  before_action :require_sign_in
  before_action :require_admin

  def update
    member = find_in_church(:users, params[:id])
    attrs  = params.require(:user).permit(:role, :name)

    if attrs.key?(:role) && demoting_last_admin?(member, attrs[:role])
      return redirect_to team_path, alert: "A church must have at least one admin."
    end

    if member.update(attrs)
      notice = attrs.key?(:role) ? "#{member.display_name} is now #{member.role}." : t("members.renamed", email: member.email)
      redirect_to team_path, notice: notice
    else
      redirect_to team_path, alert: member.errors.full_messages.to_sentence
    end
  end

  # Add a member to (or remove them from) the church's Band.
  def band
    member = find_in_church(:users, params[:id])
    in_band = ActiveModel::Type::Boolean.new.cast(params[:band_member])

    member.update!(band_member: in_band)
    key = in_band ? "members.band.added" : "members.band.removed"
    redirect_to team_path, notice: t(key, email: member.email)
  end

  def destroy
    member = find_in_church(:users, params[:id])

    if current_church.only_admin?(member)
      return redirect_to team_path, alert: "A church must have at least one admin."
    end

    member.destroy
    redirect_to team_path, notice: "#{member.email} removed."
  end

  private

  def demoting_last_admin?(member, new_role)
    member.admin? && new_role.to_s != "admin" && current_church.only_admin?(member)
  end
end
