class SessionsController < ApplicationController
  def new
    # With a subdomain church, the picker is hidden and auth is scoped to it; otherwise show all.
    @churches = Church.order(:name) unless subdomain_church
  end

  def create
    # A subdomain pins the church (approach A: login convenience); else use the picked church.
    church = subdomain_church || Church.find_by(id: params[:church_id])
    user = church&.users&.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      unless user.confirmed?
        @churches = Church.order(:name) unless subdomain_church
        @unconfirmed_email = user.email
        flash.now[:alert] = "Please confirm your email before signing in. Check your inbox, or resend the link below."
        return render :new, status: :unprocessable_entity
      end
      sign_in(user)
      redirect_to after_sign_in_path, notice: "Signed in to #{church.name}."
    else
      @churches = Church.order(:name) unless subdomain_church
      flash.now[:alert] = subdomain_church ? "Invalid email or password." : "Invalid church, email, or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out
    redirect_to login_path, notice: "Signed out."
  end

  private

  # Land on the home launchpad after sign-in.
  def after_sign_in_path
    root_path
  end
end
