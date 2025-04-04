class Reserve < ApplicationRecord
    belongs_to :user
    belongs_to :staff
    attr_accessor :frames, :start_date, :email, :gender , :tel, :name, :name_kana
    
    scope :h_nonnominated_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: "h", staff_id: 0).count }
    scope :w_nonnominated_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: "w", staff_id: 0).count }
    scope :nonnominated_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: ["w","h"], staff_id: 0).count }
    scope :h_nominated_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: "h").where.not(staff_id: 0).count }
    scope :w_nominated_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: "w").where.not(staff_id: 0).count }
    scope :nominated_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: ["w","h"]).where.not(staff_id: 0).count }
    scope :sanmei_reserved_count, -> (date, space) { where(reserved_date: date, reserved_space: space, machine: "o", staff_id: 1).count }
    scope :nominated_staff_array, -> (date, space) { where(reserved_date: date, reserved_space: space).pluck(:staff_id) }
    
    def selected_machine
        if machine == "h"
            result = "Holistic"
        elsif machine == "w"
            result = "Wellbeing"
        elsif machine == "o"
            if staff_id == 1
                result = "算命学"
            elsif staff_id == 5
                result = "腸もみ・ファスティング・栄養指導"
            else
                result = "その他"
            end
        else
            result = "その他"
        end
        return result
    end
    
    
    def self.adjust_record
        logger.debug("====================== reserve adjust_record = #{self.last.id}")
        self.last.destroy
        # export_csv_backup
        puts "adjust_record puts"
    end
    
    # private
    # def export_csv_backup
      
        # require 'csv'
        # backup_reserves = self.where(reserved_date: Date.today.months_since(-1).in_time_zone.all_month).order(:id)
        
        # CSV.generate do |csv|
        #   column_names = %w(id root_reserve_id user_id reserved_date reserved_space staff_id remarks created_at updated_at)
        #   csv << column_names
        #   backup_reserves.each_with_index do |reserve, i|
        #      i += 1
        #     column_values = [
        #       i,
        #       reserve.id,
        #       reserve.root_reserve_id,
        #       reserve.english,
        #       reserve.user_id,
        #       reserve.reserved_date,
        #       reserve.reserved_space,
        #       reserve.staff_id,  
        #       reserve.remarks,
        #       reserve.created_at,
        #       reserve.updated_at
        #     ]
        #     csv << column_values
        #   end
        # end
        
        # logger.debug("-------reserve exported #{backup_reserves.count}件")
        
#   end
    
    
end
