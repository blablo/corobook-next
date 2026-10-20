class TeamController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_admin

  def show
    @members     = church_scope(:users).order(:role, :email)
    @invitations = church_scope(:invitations).pending.order(created_at: :desc)
    @invitation  = Invitation.new(role: "editor")
  end
end
