module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!

      private

      def authenticate_api_key!
        header = request.headers["Authorization"].to_s
        api_key = header.sub(/\ABearer\s+/, "")
        stored_key = ENV.fetch("API_KEY", "")

        unless api_key.present? && stored_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, stored_key)
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end
    end
  end
end
