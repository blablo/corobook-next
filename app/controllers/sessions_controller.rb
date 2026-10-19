class SessionsController < ApplicationController
  def new
    @churches = Church.order(:name)
  end

  def create
    church = Church.find_by(id: params[:church_id])
    user = church&.users&.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      sign_in(user)
      redirect_to after_sign_in_path, notice: "Signed in to #{church.name}."
    else
      @churches = Church.order(:name)
      flash.now[:alert] = "Invalid church, email, or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out
    redirect_to login_path, notice: "Signed out."
  end

  private

  # No authenticated home exists until a later phase; land somewhere stable for now.
  def after_sign_in_path
    login_path
  end
end
