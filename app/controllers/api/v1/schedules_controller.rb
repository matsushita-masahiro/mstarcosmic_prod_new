module Api
  module V1
    class SchedulesController < BaseController
      def index
        schedules = Schedule.all
        schedules = schedules.where(schedule_date: params[:date]) if params[:date].present?
        render json: schedules
      end
    end
  end
end
