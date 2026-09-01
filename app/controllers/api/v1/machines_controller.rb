module Api
  module V1
    class MachinesController < BaseController
      def index
        render json: Machine.all
      end
    end
  end
end
