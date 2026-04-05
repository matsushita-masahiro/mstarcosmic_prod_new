module Api
  module V1
    class MachineSchedulesController < BaseController
      def index
        machine_schedules = MachineSchedule.all
        machine_schedules = machine_schedules.where(machine_schedule_date: params[:date]) if params[:date].present?
        render json: machine_schedules
      end
    end
  end
end
