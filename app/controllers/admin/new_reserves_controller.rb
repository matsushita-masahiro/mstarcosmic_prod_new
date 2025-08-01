class Admin::NewReservesController < ApplicationController
  before_action :authenticate_admin!
  def index
    @new_reserves = NewReserve.includes(:user, :new_staff)
                              .order(date: :asc, start_time_slot: :asc)
  end

  def show
    @new_reserve = NewReserve.find(params[:id])
  end

  def destroy
    @new_reserve = NewReserve.find(params[:id])
    @new_reserve.destroy
    redirect_to admin_new_reserves_path, notice: '予約を削除しました。'
  end
end
