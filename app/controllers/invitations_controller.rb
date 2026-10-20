class InvitationsController < ApplicationController
  before_action :require_sign_in
  before_action :require_admin

  def create
    email = Invitation.new(email: params.dig(:invitation, :email)).email # normalize via model
    role  = params.dig(:invitation, :role)

    if email.present? && church_scope(:users).exists?(email: email)
      return redirect_to team_path, alert: "That person is already a member."
    end

    invitation = church_scope(:invitations).pending.find_by(email: email) ||
                 church_scope(:invitations).new(email: email)
    invitation.assign_attributes(role: role, invited_by: current_user)
    invitation.regenerate_token!

    if invitation.save
      deliver(invitation)
      redirect_to team_path,
                  notice: "Invitation sent to #{invitation.email}.",
                  flash: { accept_url: accept_invitation_url(token: invitation.raw_token) }
    else
      redirect_to team_path, alert: invitation.errors.full_messages.to_sentence
    end
  end

  def resend
    invitation = find_in_church(:invitations, params[:id])
    invitation.regenerate_token!
    invitation.save!
    deliver(invitation)
    redirect_to team_path,
                notice: "Invitation to #{invitation.email} re-sent.",
                flash: { accept_url: accept_invitation_url(token: invitation.raw_token) }
  end

  def destroy
    invitation = find_in_church(:invitations, params[:id])
    invitation.destroy
    redirect_to team_path, notice: "Invitation to #{invitation.email} revoked."
  end

  private

  # Best-effort delivery: the invitation is authoritative, mail is a side effect (D-U10).
  def deliver(invitation)
    InvitationsMailer.invite(invitation, invitation.raw_token).deliver_later
  rescue StandardError => e
    Rails.logger.warn("Invitation mail enqueue failed: #{e.class}: #{e.message}")
  end
end
