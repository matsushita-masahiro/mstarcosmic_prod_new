class Admin::BusinessTripsController < ApplicationController
    before_action :authenticate_admin!
    
    def index
      @start_date = params[:date]&.to_date || Date.current
      @dates = (0..6).map { |i| @start_date + i.days }
      @time_slots = generate_time_slots
      @machines = NewMachine.all.order(:name)
      @selected_machine = params[:machine_id].present? ? NewMachine.find(params[:machine_id]) : @machines.first
      
      if @selected_machine
        @weekly_business_trips = get_weekly_business_trips(@selected_machine, @dates)
      end
    end
  
    def create
      @business_trip = BusinessTrip.new(business_trip_params)
      
      if @business_trip.save
        render json: { status: 'success', message: '出張スケジュールを登録しました' }
      else
        render json: { status: 'error', errors: @business_trip.errors.full_messages }
      end
    end
  
    def destroy
      @business_trip = BusinessTrip.find(params[:id])
      @business_trip.destroy
      render json: { status: 'success', message: '出張スケジュールを削除しました' }
    end
  
    private
  

    def business_trip_params
      params.require(:business_trip).permit(:machine_id, :date, :time_slot)
    end
  
    def generate_time_slots
      slots = []
      (0..23).each do |slot|
        hour = 10 + (slot / 2)
        minute = (slot % 2) * 30
        break if hour > 21 || (hour == 21 && minute > 30)
        
        time_str = "#{hour.to_s.rjust(2, '0')}:#{minute.to_s.rjust(2, '0')}"
        slots << { slot: slot, time: time_str }
      end
      slots
    end

    def get_weekly_business_trips(machine, dates)
      weekly_business_trips = {}
      
      dates.each do |date|
        weekly_business_trips[date] = {}
        @time_slots.each do |time_data|
          slot = time_data[:slot]
          
          business_trip = BusinessTrip.find_by(
            new_machine_id: machine.id,
            date: date,
            time_slot: slot
          )
          
          weekly_business_trips[date][slot] = business_trip.present?
        end
      end
      
      weekly_business_trips
    end
  end