module ReservationsHelper
    
    def reserved_check(date,frame)
        if Reservation.find_by(reserved_date: date, reserved_space: frame)
            reservation = Reservation.find_by(reserved_date: date, reserved_space: frame)
            return reservation
        end
    end
    
    
    def display_time(x)
        if x-x.to_i == 0
            result = "#{x.to_i}:00"
        else
            result = "#{x.to_i}:#{((x-x.to_i)*60).to_i}"
        end
        
        return  result 
    end
    
end
