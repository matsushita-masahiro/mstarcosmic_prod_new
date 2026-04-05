module Api
  module V1
    class StaffsController < BaseController
      def index
        render json: Staff.all
      end
    end
  end
end
