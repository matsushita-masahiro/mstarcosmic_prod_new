class Reserve < ApplicationRecord
    belongs_to :user
    belongs_to :staff
    attr_accessor :frames, :start_date, :email, :gender , :tel, :name, :name_kana

    # 並行稼働: 旧reservesに書き込まれたら新reservationsにも同期
    after_create :sync_to_reservations
    after_destroy :remove_from_reservations
    
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
    private

    def sync_to_reservations
      return if user_id == 0 # 休日レコードはスキップ
      # root_reserve_idが自分自身の場合のみ同期（親レコード）
      # root_reserve_idがまだ設定されていない場合も同期（後でupdateされる）
      return if root_reserve_id.present? && root_reserve_id != id

      # 同じroot_reserve_idのグループを集めて1件のReservationにする
      # ただしcreate直後はroot_reserve_idがまだnilの場合があるので、
      # after_updateでも同期する
    end

    def remove_from_reservations
      # 対応するReservationを削除
      return if user_id == 0

      group = Reserve.where(root_reserve_id: root_reserve_id || id)
      return if group.empty?

      min_space = group.minimum(:reserved_space)
      h = min_space.to_i
      m = ((min_space - h) * 60).round
      start_t = format('%02d:%02d', h, m)

      service = case machine
                when 'h' then 'holistic'
                when 'w' then 'holistic'
                when 'e' then 'esute'
                when 'seitai' then 'seitai'
                else 'holistic'
                end

      Reservation.where(
        user_id: user_id,
        date: reserved_date,
        start_time: start_t,
        service: service
      ).destroy_all
    rescue => e
      Rails.logger.warn "Reserve#remove_from_reservations: #{e.message}"
    end

    # root_reserve_id設定後に呼ばれる
    after_update :sync_group_to_reservations_if_root
    # 子レコード作成時にも親グループを再同期
    after_create :sync_parent_group
    after_update :sync_parent_group_on_update

    def sync_group_to_reservations_if_root
      return unless saved_change_to_root_reserve_id?
      sync_group_to_reservations
    end

    def sync_parent_group
      return if user_id == 0
      return if root_reserve_id.nil? || root_reserve_id == id
      parent = Reserve.find_by(id: root_reserve_id)
      parent&.send(:sync_group_to_reservations)
    end

    def sync_parent_group_on_update
      return unless saved_change_to_root_reserve_id?
      return if user_id == 0
      return if root_reserve_id.nil? || root_reserve_id == id
      parent = Reserve.find_by(id: root_reserve_id)
      parent&.send(:sync_group_to_reservations)
    end

    def sync_group_to_reservations
      return if user_id == 0
      return unless root_reserve_id == id # 親レコードのみ

      group = Reserve.where(root_reserve_id: id).order(:reserved_space)
      return if group.empty?

      min_space = group.minimum(:reserved_space)
      max_space = group.maximum(:reserved_space)
      duration = group.count * 30

      service = case machine
                when 'h' then 'holistic'
                when 'w' then 'holistic'
                when 'e' then 'esute'
                when 'seitai' then 'seitai'
                else 'holistic'
                end

      h = min_space.to_i
      m = ((min_space - h) * 60).round
      start_time = format('%02d:%02d', h, m)

      end_h = (max_space + 0.5).to_i
      end_m = (((max_space + 0.5) - end_h) * 60).round
      end_time = format('%02d:%02d', end_h, end_m)

      staff_id_val = staff_id == 0 ? nil : staff_id

      # 指名なし(staff_id=0)の場合、自動割当
      if staff_id_val.nil?
        slot_time = start_time
        svc = AvailabilityService.new(service, reserved_date, num_days: 1, user_signed_in: true)
        assigned = svc.auto_assign_staff(reserved_date, slot_time, duration_minutes: duration)
        staff_id_val = assigned&.id
      end

      existing = Reservation.find_by(
        user_id: user_id, date: reserved_date,
        start_time: start_time, service: service
      )

      if existing
        existing.update!(
          staff_id: staff_id_val, end_time: end_time,
          duration: duration, notes: remarks,
          is_new_customer: new_customer || false
        )
      else
        Reservation.create!(
          user_id: user_id, staff_id: staff_id_val,
          service: service, date: reserved_date,
          start_time: start_time, end_time: end_time,
          duration: duration, is_new_customer: new_customer || false,
          notes: remarks, status: 0,
          group_id: SecureRandom.uuid
        )
      end
    rescue => e
      Rails.logger.warn "Reserve#sync_group_to_reservations: #{e.message}"
    end
    
    
end
