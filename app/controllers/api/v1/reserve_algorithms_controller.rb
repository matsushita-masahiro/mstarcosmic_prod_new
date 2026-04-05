module Api
  module V1
    class ReserveAlgorithmsController < BaseController
      def index
        render json: ReserveAlgorithm.all
      end
    end
  end
end
