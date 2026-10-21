class RegistrationsController < ApplicationController
  layout "public"
  before_action :redirect_if_signed_in

  def new
    @church = Church.new
    @user = User.new
  end

  def create
    @church = Church.new(church_params)
    @user = @church.users.build(user_params.merge(role: "admin"))

    ActiveRecord::Base.transaction do
      @church.save!
      @user.save!
    end
    sign_in(@user)
    redirect_to root_path, notice: "Welcome to Corobook, #{@church.name}!"
  rescue ActiveRecord::RecordInvalid
    # Surface errors from whichever record failed; the transaction rolled back, so nothing persisted.
    flash.now[:alert] = (@church.errors.full_messages + @user.errors.full_messages).to_sentence.presence ||
                        "Could not create your account."
    render :new, status: :unprocessable_entity
  end

  private

  def church_params
    params.require(:church).permit(:name, :subdomain)
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def redirect_if_signed_in
    redirect_to root_path if signed_in?
  end
end
