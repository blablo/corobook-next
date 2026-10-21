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
  rescue ActiveRecord::RecordNotUnique => e
    # The DB unique index fired where the model validation's check-then-save window raced (two
    # signups grabbing the same subdomain at once). Turn the 500 into the same friendly error.
    if e.message.include?("subdomain")
      @church.errors.add(:subdomain, "has already been taken")
    else
      @church.errors.add(:base, "Could not create your account. Please try again.")
    end
    flash.now[:alert] = @church.errors.full_messages.to_sentence
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
