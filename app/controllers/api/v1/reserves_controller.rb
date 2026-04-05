module Api
  module V1
    class ReservesController < BaseController
      before_action :set_reserve, only: %i[show update]

      def index
        reserves = Reserve.all
        reserves = reserves.where(reserved_date: params[:date]) if params[:date].present?
        render json: reserves
      end

      def show
        render json: @reserve
      end

      def create
        reserve = Reserve.new(reserve_params)
        if reserve.save
          render json: reserve, status: :created
        else
          render json: { errors: reserve.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @reserve.update(reserve_params)
          render json: @reserve
        else
          render json: { errors: @reserve.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_reserve
        @reserve = Reserve.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Reserve not found" }, status: :not_found
      end

      def reserve_params
        params.require(:reserve).permit(
          :user_id, :reserved_date, :remarks, :reserved_space,
          :root_reserve_id, :staff_id, :machine, :new_customer
        )
      end
    end
  end
end
