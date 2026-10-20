class MembersController < ApplicationController
  before_action :require_sign_in
  before_action :require_admin

  def update
    member   = find_in_church(:users, params[:id])
    new_role = params.dig(:user, :role)

    if demoting_last_admin?(member, new_role)
      return redirect_to team_path, alert: "A church must have at least one admin."
    end

    if member.update(role: new_role)
      redirect_to team_path, notice: "#{member.email} is now #{member.role}."
    else
      redirect_to team_path, alert: member.errors.full_messages.to_sentence
    end
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
