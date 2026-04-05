module Api
  module V1
    class StaffMachineRelationsController < BaseController
      def index
        render json: StaffMachineRelation.all
      end
    end
  end
end
