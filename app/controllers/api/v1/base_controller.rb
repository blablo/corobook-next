module Api
  module V1
    # Token-authenticated JSON API. Not a browser surface: no session, no CSRF, no redirects.
    # Tenancy comes from the token's user, exactly like the UI (Current.church).
    class BaseController < ActionController::API
      before_action :authenticate_token

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end
      rescue_from ActionController::ParameterMissing do |e|
        render json: { error: "param_missing", param: e.param }, status: :bad_request
      end

      private

      def authenticate_token
        raw = request.authorization.to_s[/\ABearer (.+)\z/, 1]
        token = ApiToken.authenticate(raw)
        user = token&.user
        return render json: { error: "unauthorized" }, status: :unauthorized unless user
        return render json: { error: "forbidden" }, status: :forbidden unless user.admin? || user.editor?

        token.update_column(:last_used_at, Time.current) if token.last_used_at.nil? || token.last_used_at < 1.minute.ago
        Current.user = user
        Current.church = user.church
      end

      def church = Current.church

      def dry_run? = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false
    end
  end
end
