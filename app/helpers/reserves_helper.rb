module ReservesHelper
    
    def reserved_record(date,space)
        if reserve = Reserve.find_by(reserved_date: date, reserved_space: space)
            return reserve
        end
    end
 
    # calender_machine calender_machine_admin 用  from 2021/11/16 指定なしは無し
    def reserved_status(staff, date, space)
        
            if schedule = Schedule.find_by(user_id: staff.user_id, schedule_date: date, schedule_space: space)  # 出勤
                if Reserve.find_by(reserved_date: date, reserved_space: space)  # 予約有無
                    reserves = Reserve.where(reserved_date: date, reserved_space: space)
                else
                    reserves = nil
                end
                
                if !reserves.nil? && reserves.count == 2
                    result = ["reserved", reserves]  # ✖️
                else
                    if staff.id === 6 # wellbeingなら
                        if reserves.nil?
                           result =  ["reservable_two", nil]   # ◎
                        elsif reserves.count === 1
                           result = ["reservable_one", reserves]  # △
                        elsif reserves.count === 2
                           result = ["reserved", reserves]  # ✖️
                        end
                    else  # holisticなら
                        if reserves.nil? || (reserves.count == 1 && !Reserve.find_by(staff_id: staff.id, reserved_date: date, reserved_space: space))# 予約０件
                           result = ["reservable_one", nil]
                        elsif reserves.count == 1 && Reserve.find_by(staff_id: staff.id, reserved_date: date, reserved_space: space)   # このスタッフの予約あり
                           result = ["reserved", reserves]  # ✖️
                        else 
                           result = ["reserved", reserves]  # ✖️
                        end                
                    end
                end
          
            else  # 欠勤
                result = ["absence",nil]
            end
        
        logger.debug("~~~~~~~~~~~~~~~~~~~~^ result = #{result} あれ・")
        return result
        
    end
    
    
    # 2022/2/10 新予約システム対応アルゴリズム
    # def reserve_availability(machine, staff, date, space)
      
    #   if Reserve.where(reserved_date: date, reserved_space: space, machine: machine).count == 2
    #     return ["reserved", Reserve.where(reserved_date: date, reserved_space: space)]  # ✖️
    #   end

    #   # holistic or wellbeing
    #   if machine == "h" || machine == "w"
    #       # そのマシンを使えるスタッフ
    #       if StaffMachineRelation.find_by(machine: machine)
    #         # not(staff_id: [0,4])は 指名なしの場合はstaff 0 と 奈緒は出勤してないことにする 2022/4/20 
    #         can_staffs = staff.id == 0 ? StaffMachineRelation.where(machine: machine).where.not(staff_id: 0).pluck(:staff_id) : staff.id
    #         # その枠に出勤しているそのマシンが使えるスタッフ配列
    #         if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: can_staffs)
    #           # 引数staff_idがnilならスタッフ指名無しなのでその機械が使えるスタッフのid配列をnilでなければ引数staff_idをattendancesに代入する
    #           attendances = staff.id == 0 ? Schedule.where(schedule_date: date, schedule_space: space, staff_id: can_staffs).pluck(:staff_id) : [staff.id]
              
    #           logger.debug("---------- id reserve_availability date #{date} space #{space} can_staffs = #{can_staffs} attendances = #{attendances}")
    #         # その枠にそのスタッフ（可能スタッフ）の予約がすでに入っているか
            

    #           plus_non_nomination_attendancs = [0] + attendances
    #           if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: plus_non_nomination_attendancs) 
                
    #             logger.debug("============================== plus_non_nomination_attendancs = #{plus_non_nomination_attendancs}")
    #             reserves = Reserve.where(reserved_date: date, reserved_space: space, staff_id: plus_non_nomination_attendancs)
    #             logger.debug("============================== その枠の予約数 = #{reserves.count}")
    #             # 予約不可
    #           else
    #             # その枠にその機械を使えるスタッフの予約が入ってない
    #             logger.debug("============================== その枠の予約数ゼロ")
                
    #             reserves = []
    #             # 予約可能
    #           end
    #           # 予約可能数(result)
    #           availabilities = attendances.count - reserves.count
    #         #   availabilities = availabilities - 1
    #           logger.debug("^^^^^^^^^^^^^^^^^^^^^^ attendances.count(#{attendances.count}) - reserves.count(#{reserves.count})")
    #         #   聖子が出勤している場合で算命学予約入ってない施術者数を１増やす
    #           if attendances.include?(1) && !Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "o")
    #               availabilities = availabilities + 1
    #               logger.debug("============================== 聖子出勤 availabilities = #{availabilities}")
    #           else
    #               logger.debug("============================== 聖子出勤してない availabilities = #{availabilities}")
    #           end
    #         else
    #           # その枠に出勤しているHolisticが使えるスタッフ不在
    #           availabilities = nil
    #         end
            
    #         if Reserve.find_by(reserved_date: date, reserved_space: space)
    #             reserved_infos = Reserve.where(reserved_date: date, reserved_space: space)
    #         else
    #             reserved_infos = nil
    #         end
            
    #         if availabilities == 2  || availabilities == 3 || availabilities == 4  || availabilities == 5
    #           result = ["reservable_two", reserved_infos]   # ◎
    #         elsif availabilities == 1
    #           result = ["reservable_one", reserved_infos]  # △
    #         elsif availabilities == 0
    #           result = ["reserved", reserved_infos]  # ✖️
    #         elsif availabilities == nil
    #           result = ["non_scheduled", reserved_infos]
    #         else
    #           flash[:error] = "エラー発生"
    #           result = ["reserved", reserved_infos]  # ✖️
    #         end

    #       else
    #         # holisticを使えるスタッフ未設定
    #         flash[:error] = "Holisticを使えるスタッフが未設定です"
    #         result = ["reserved", reserved_infos]  # ✖️
    #       end

    #   elsif machine == "o"
        
    #     if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: staff.id)
    #       if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: staff.id) 
    #         # 出勤&予約あり
    #         result = ["reserved", Reserve.where(reserved_date: date, reserved_space: space, staff_id: staff.id)]
    #       else
    #         # 出勤&予約無し
    #         result = ["reservable_one", nil]
    #       end
    #     else
    #       # 出勤なし
    #       result = ["non_scheduled", nil]
    #     end
        
    #   else
    #     # 機械が指定されてません
    #     flash[:error] = "machineが選択されていません"
    #     result = ["reserved", reserved_infos]  # ✖️
    #   end
    #   logger.debug("=============== result = #{result}")
    #   return result
      
    # end

    # 2022/6/6 machine台数対応アルゴリズム (staff_id=0は指名なし)
    # def reserve_availability_machine_number_support(machine, staff, date, space)
      
    #     wellbeing_numbers = Machine.find_by(short_word: "w").number_of_machine
    #     holistic_numbers = Machine.find_by(short_word: "h").number_of_machine
    #     machine_numbers_hash = {w: wellbeing_numbers, h: holistic_numbers}
    #     logger.debug("---------- new_reserve_availability_20220620 machine=#{machine} space #{space} staff = #{staff.id} machine_hash = #{machine_numbers_hash}")
        
    #     # 予約可能数(result)
    #     if !Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: staff.id)
    #       logger.debug("---------- 出勤していない schedule_date: #{date}, schedule_space: #{space}")
    #       result = ["non_scheduled", nil] # ==        
    #     elsif machine == "w" && (Reserve.where(reserved_date: date, reserved_space: space, machine: machine).length >= wellbeing_numbers)
    #       result =  ["reserved", Reserve.where(reserved_date: date, reserved_space: space)]  # ✖
    #     elsif machine == "h" && (Reserve.where(reserved_date: date, reserved_space: space, machine: machine).length >= holistic_numbers)
    #       result = ["reserved", Reserve.where(reserved_date: date, reserved_space: space)]  # ✖
    #     else
        
  
    #       # holistic or wellbeing
    #       if machine == "h" || machine == "w"
    #           # そのマシンを使えるスタッフ
    #           if StaffMachineRelation.find_by(machine: machine)
    #             # not(staff_id: [0,4])は 指名なしの場合はstaff 0 と 奈緒は出勤してないことにする 2022/4/20 
    #             can_staffs = StaffMachineRelation.where(machine: machine).where.not(staff_id: 0).pluck(:staff_id)
    #             # can_staffs = staff.id == 0 ? StaffMachineRelation.where(machine: machine).where.not(staff_id: 0).pluck(:staff_id) : staff.id
    #             # その枠に出勤しているそのマシンが使えるスタッフ配列
    #             if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: can_staffs)
    #               # 引数staff_idがnilならスタッフ指名無しなのでその機械が使えるスタッフのid配列をnilでなければ引数staff_idをattendancesに代入する
    #               # attendances = Schedule.where(schedule_date: date, schedule_space: space, staff_id: can_staffs).pluck(:staff_id)
    #               attendances = staff.id == 0 ? Schedule.where(schedule_date: date, schedule_space: space, staff_id: can_staffs).pluck(:staff_id) : [staff.id]
                  
    #               logger.debug("---------- id reserve_availability date #{date} space #{space} can_staffs = #{can_staffs} attendances = #{attendances}")
    #             # その枠にそのスタッフ（可能スタッフ）の予約がすでに入っているか
                
    
    #               plus_non_nomination_attendancs = [0] + attendances
    #               if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: plus_non_nomination_attendancs) 
                    
    #                 logger.debug("============================== plus_non_nomination_attendancs = #{plus_non_nomination_attendancs}")
    #                 reserves = Reserve.where(reserved_date: date, reserved_space: space, staff_id: plus_non_nomination_attendancs)
    #                 logger.debug("============================== その枠の予約数 = #{reserves.count}")
    #                 # 予約不可
    #               else
    #                 # その枠にその機械を使えるスタッフの予約が入ってない
    #                 logger.debug("============================== その枠の予約数ゼロ")
                    
    #                 reserves = []
    #                 # 予約可能
    #               end
    #               # 予約可能数(result)
    #               availabilities = attendances.count - reserves.count
    #             #   availabilities = availabilities - 1
    #               logger.debug("^^^^^^^^^^^^^^^^^^^^^^ attendances.count(#{attendances.count}) - reserves.count(#{reserves.count})")
    #             #   聖子が出勤している場合で算命学予約入ってない施術者数を１増やす
    #               if attendances.include?(1) && !Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "o")
    #                   availabilities = availabilities + 1
    #                   logger.debug("============================== 聖子出勤 availabilities = #{availabilities}")
    #               else
    #                   logger.debug("============================== 聖子出勤してない availabilities = #{availabilities}")
    #               end
    #             else
    #               # その枠に出勤しているHolisticが使えるスタッフ不在
    #               availabilities = nil
    #             end
                
    #             if Reserve.find_by(reserved_date: date, reserved_space: space)
    #                 reserved_infos = Reserve.where(reserved_date: date, reserved_space: space)
    #             else
    #                 reserved_infos = nil
    #             end
                
               
    #             # マシン残り台数検査
                
    #             number_of_left_machine = Machine.find_by(short_word: machine).number_of_machine - Reserve.where(reserved_date: date, reserved_space: space, machine: machine).count
    #             if number_of_left_machine == 1 && availabilities.present? && (availabilities >= 2)
    #               availabilities = 1
    #             end             
  
    #             if availabilities == 2  || availabilities == 3 || availabilities == 4  || availabilities == 5
    #               result = ["reservable_two", reserved_infos]   # ◎
    #             elsif availabilities == 1
    #               result = ["reservable_one", reserved_infos]  # △
    #             elsif availabilities == 0
    #               result = ["reserved", reserved_infos]  # ✖️
    #             elsif availabilities == nil
    #               result = ["non_scheduled", reserved_infos]
    #             else
    #               flash[:error] = "エラー発生"
    #               result = ["reserved", reserved_infos]  # ✖️
    #             end
    
    #           else
    #             # holisticを使えるスタッフ未設定
    #             flash[:error] = "Holisticを使えるスタッフが未設定です"
    #             result = ["reserved", reserved_infos]  # ✖️
    #           end
    
    #       elsif machine == "o"
            
    #         if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: staff.id)
    #           if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: staff.id) 
    #             # 出勤&予約あり
    #             result = ["reserved", Reserve.where(reserved_date: date, reserved_space: space, staff_id: staff.id)]
    #           else
    #             # 出勤&予約無し
    #             result = ["reservable_one", nil]
    #           end
    #         else
    #           # 出勤なし
    #           result = ["non_scheduled", nil]
    #         end
            
    #       else
    #         # 機械が指定されてません
    #         flash[:error] = "machineが選択されていません"
    #         result = ["reserved", reserved_infos]  # ✖️
    #       end
    #     end
    #     logger.debug("=============== result = #{result}")
    #     return result
      
    # end
    
    
    def new_reserve_availability_20220620(machine, staff, date, space)
      
        logger.debug("^^^^^^^^^^^^^^^^^^^^^ MachineSchedule = #{machine_schedule(date, space, machine)}")
        reserved_infos = Reserve.where(reserved_date: date, reserved_space: space)

      
        wellbeing_numbers = Machine.find_by(short_word: "w").number_of_machine
        holistic_numbers = Machine.find_by(short_word: "h").number_of_machine
        machine_numbers_hash = {"w" =>  wellbeing_numbers, "h" => holistic_numbers}
        vacant_wellbeing = machine_numbers_hash["w"] - Reserve.where(reserved_date: date, reserved_space: space, machine: "w").count
        vacant_holistic = machine_numbers_hash["h"] - Reserve.where(reserved_date: date, reserved_space: space, machine: "h").count
        # そのmachineを使えるスタッフarr
        can_staffs_arr = StaffMachineRelation.where(machine: machine).where.not(staff_id: 0).pluck(:staff_id)
        # その枠にそのmachineを使える出勤しているスタッフarr
        attendances_arr = Schedule.where(schedule_date: date, schedule_space: space, staff_id: can_staffs_arr).pluck(:staff_id)
        # 指名なし予約数
        non_nominated_reserve_count = Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0).count
        # その枠に予約済みにスタッフ
        reserved_staffs_arr = Reserve.where(reserved_date: date, reserved_space: space, staff_id: attendances_arr).pluck(:staff_id)

        # vacant_staffs_arr は 空いてるスタッフidの配列(鹿田は2人として計算している)
        if attendances_arr.include?(1) 
          # 鹿田出勤している
            if machine == "o" && staff.id == 1
              logger.debug("================ sannmei Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0).count = #{Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0 ).count}")
              # 算命学の予約可能か
              if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1)
                # その枠に鹿田の予約が何かしら入っていたら
                vacant_staffs_arr = attendances_arr - [1]
              elsif (non_nominated_reserve_count === attendances_arr.count)
                # その枠に鹿田の予約が何かしら入ってなかったら
                vacant_staffs_arr = []
              else
                vacant_staffs_arr = attendances_arr
              end
            else
              if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "o")
                # 算命学が予約入っていた場合
                vacant_staffs_arr = attendances_arr - [1] - reserved_staffs_arr
              elsif (masako_available_count(date, space, machine) == 2)
                # 算命学予約入っていなく、鹿田のh,wの予約入ってない場合
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr + [1]
              elsif (masako_available_count(date, space, machine) == 1)
                # 算命学予約入ってなくて,鹿田のh,wの予約が1つ入っている
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr + [1]
              elsif (masako_available_count(date, space, machine) == 0)
                # 算命学予約入ってなくて,鹿田のh,wの予約が2つ入っている
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr
              else
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr
              end
            end
        else # 鹿田が出勤してない場合
          vacant_staffs_arr = attendances_arr - reserved_staffs_arr
        end
        
      
    
        if attendances_arr.present?  
            # 施術可能スタッフ出勤していたら
            if machine == "h"
              if staff.id == 0 # 指名なし
                logger.debug("======================== space = #{space} holistic 指名なし reserved_infos.count = #{reserved_infos.count} vacant_holistic = #{vacant_holistic} vacant_staffs_arr = #{vacant_staffs_arr}")
                if (attendances_arr-[1]).count == 0
                  available_count = [vacant_holistic, masako_available_count(date, space, machine)+(attendances_arr-[1]).count-reserved_staffs_arr.count].sort[0]
                else
                  available_count = [vacant_holistic, masako_available_count(date, space, machine)+(attendances_arr-[1]).count-reserved_staffs_arr.count-non_nominated_reserve_count].sort[0]
                end
                vacant_holistic_nonominated = available_count
                logger.debug("~~~~~~~~~~~~~~~~~ masako_available_count = #{masako_available_count(date, space, machine)}  vacant_holistic = #{vacant_holistic} available_count = #{available_count} attendances_arr = #{attendances_arr}")
    
                    if vacant_holistic_nonominated == 2  # machine2台空きある
                      if vacant_staffs_arr.count >= 2  # スタッフ2人空きある
                        result = ["reservable_two", reserved_infos]   # ◎ 
                      elsif vacant_staffs_arr.count == 1 #スタッフ1人空きがある
                        result = ["reservable_one", reserved_infos]  # △
                        logger.debug("======================== holistic 指名なし reservable_one reserved_infos count = #{reserved_infos.count}}}")
                      else  #スタッフ空きなし
                        result = ["reserved", reserved_infos]  # ✖️
                        logger.debug("======================== holistic 指名なし reserved }")
                      end
                      # result = ["non_scheduled", reserved_infos]
                    elsif  vacant_holistic_nonominated == 1  # machine1台空きある
                      if vacant_staffs_arr.count >= 1  # スタッフ1人以上空きある
                        if can_staffs_arr.include?(1)
                          can_do_staff_number = attendances_arr.count + 1
                          all_reserve_count = Reserve.where(reserved_date: date, reserved_space: space, machine: ["h"]).count
                          if (can_do_staff_number - all_reserve_count) >= 1
                             logger.debug("======================== (can_do_staff_number(#{can_do_staff_number}) - all_reserve_count(#{all_reserve_count}})) >= 1 vacant_staffs_arr = #{vacant_staffs_arr}}}")
                             result = ["reservable_one", reserved_infos]  # △
                          else
                             logger.debug("======================== (can_do_staff_number(#{can_do_staff_number}) - all_reserve_count(#{all_reserve_count}})) < 1}")
                            result = ["reserved", reserved_infos]  # ✖️
                          end
                        else
                        end
                      else #スタッフ空きなし
                        logger.debug("================== スタッフ空きなし")
                        result = ["reserved", reserved_infos]  # ✖️
                      end          
                    else 
                      # machine空きなし
                      logger.debug("================== machine空きなし vacant_holistic_nonominated =#{vacant_holistic_nonominated} vacant_holistic = #{vacant_holistic} masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                      result = ["reserved", reserved_infos]  # ✖️
                    end
              else 
              # 指名あり
                # 指名スタッフ出勤している
                if attendances_arr.include?(staff.id)
                  
                      if staff.id != 1 # 指名が鹿田でないなら
                      
                        if vacant_holistic >= 2  # machine2台以上空きある
                        
                          if vacant_staffs_arr.include?(1) && !staff.id == 1  # 鹿田空いてる
                            if masako_available_count(date, space, machine) >= 2
                              result = ["reservable_two", reserved_infos]   # ◎ 
                            elsif masako_available_count(date, space, machine) == 1
                              result = ["reservable_one", reserved_infos]  # △
                            else
                              result = ["reserved", reserved_infos]  # ✖️
                            end
                            
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id == 1  # スタッフ空きある
                            result = ["reservable_two", reserved_infos]   # ◎ 
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id != 1  # スタッフ空きある
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end 
                          
                        elsif vacant_holistic == 1  # machine1台空きある
                          if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                           logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end         
                        else # machine空きなし
                          result = ["reserved", reserved_infos]  # ✖️
                        end
                        
                      else
                        # 鹿田なら
                        if vacant_holistic >= 2 && (masako_available_count(date, space, machine) >= 2)  # machine2台以上空きある
                        
                          if vacant_staffs_arr.include?(1) && !staff.id == 1  # 鹿田空いてる
                            if masako_available_count(date, space, machine) >= 2
                              result = ["reservable_two", reserved_infos]   # ◎ 
                            elsif masako_available_count(date, space, machine) == 1
                              result = ["reservable_one", reserved_infos]  # △
                            else
                              result = ["reserved", reserved_infos]  # ✖️
                            end
                            
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id == 1  # スタッフ空きある
                            result = ["reservable_two", reserved_infos]   # ◎ 
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id != 1  # スタッフ空きある
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end 
                          
                        elsif vacant_holistic == 2 && (masako_available_count(date, space, machine) >= 1)  # machine1台空きある
                          if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                           logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end                          
                        elsif vacant_holistic == 1 && (masako_available_count(date, space, machine) >= 1)  # machine1台空きある
                          if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                           logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end
                        else
                          # machine空きなし
                          logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり 439 vacant_holistic == #{vacant_holistic} && (masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}})")
                          result = ["reserved", reserved_infos]  # ✖️
                        end  
                      end
                else
                  # 指名スタッフ出勤していない
                  result = ["non_scheduled", reserved_infos]
                end
              end
            elsif machine == "w"
              if staff.id == 0 # 指名なし
                if vacant_wellbeing == 2  # machine2台空きある
                  if vacant_staffs_arr >= 2  # スタッフ2人空きある
                    result = ["reservable_two", reserved_infos]   # ◎ 
                  elsif vacant_staffs_arr.count == 1 #スタッフ1人空きがある
                    result = ["reservable_one", reserved_infos]  # △
                  else  #スタッフ空きなし
                    result = ["reserved", reserved_infos]  # ✖️
                  end
                elsif vacant_wellbeing == 1  # machine1台空きある
                  if vacant_staffs_arr.count >= 1  # スタッフ1人以上空きある
                    result = ["reservable_one", reserved_infos]  # △
                  else #スタッフ空きなし
                    result = ["reserved", reserved_infos]  # ✖️
                  end          
                else # machine空きなし
                  result = ["reserved", reserved_infos]  # ✖️
                end
              else 
                # 指名あり
                # 指名スタッフ出勤している
                  if attendances_arr.include?(staff.id)
                      if vacant_wellbeing >= 1  # machine1台以上空きある
                        if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                          result = ["reservable_one", reserved_infos]  # △
                        else  #スタッフ空きなし
                          result = ["reserved", reserved_infos]  # ✖️
                        end         
                      else # machine空きなし
                        result = ["reserved", reserved_infos]  # ✖️
                      end
                  else
                    # 指名スタッフ出勤していない
                    result = ["non_scheduled", reserved_infos]
                  end
                      
              end
            elsif machine == "o" && staff.id == 1     # 算命学
               logger.debug("~~~~~~~~~~~~~~~~~~~~~~ masako_available_count(date, space, machine) #{masako_available_count(date, space, machine)}")
               if !attendances_arr.include?(1)
                # 鹿田出勤してないなら
                  result = ["non_scheduled", reserved_infos]
               else
                # 鹿田出勤してる
                  logger.debug("||||===================  machine = o , reserved_infos.count = #{reserved_infos.count} vacant_staffs_arr = #{vacant_staffs_arr}in helper ")
                  if vacant_staffs_arr.include?(1)
                    if masako_available_count(date, space, machine) >= 1
                      # 鹿田の予約入ってないなら
                      result = ["reservable_one", reserved_infos]  # △                      
                    # 鹿田が稼働しているなら
                    # masako_reserved = Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1)
                    else
                      logger.debug("||||=================== 1")
                      result = ["reserved", reserved_infos]  # ✖️
                    end
                  else
                    logger.debug("||||=================== 2")
                    result = ["reserved", reserved_infos]  # ✖️
                  end
              end
            
            elsif machine == "o" && staff.id == 5 # (夏子腸もみ・ファスティング)
                if !attendances_arr.include?(5)
                  # 夏子出勤していないなら
                    result = ["non_scheduled", reserved_infos]
                else 
                    if !vacant_staffs_arr.include?(5)
                      # 夏子予約入っているなら
                       result = ["reserved", reserved_infos]  # ✖️
                    else
                      # 夏子の予約入ってないなら
                       result = ["reservable_one", reserved_infos]  # △
                    end
                end
              
            elsif machine == "o" && staff.id == 8 # 佐藤
                if !attendances_arr.include?(8)
                  # 佐藤出勤していないなら
                    result = ["non_scheduled", reserved_infos]
                else 
                    if !vacant_staffs_arr.include?(8)
                      # 佐藤予約入っているなら
                       result = ["reserved", reserved_infos]  # ✖️
                    else
                      # 佐藤の予約入ってないなら
                       result = ["reservable_one", reserved_infos]  # △
                    end
                end
            else 
              # その他のその他スタッフ
                if !attendances_arr.include?(staff.id)
                  # 出勤していないなら
                    result = ["non_scheduled", reserved_infos]
                else 
                    if !vacant_staffs_arr.include?(staff.id)
                      # 予約入っているなら
                       result = ["reserved", reserved_infos]  # ✖️
                    else
                      # 予約入ってないなら
                       result = ["reservable_one", reserved_infos]  # △
                    end
                end        
            end
        else
          # 施術可能スタッフ出勤してない
          result = ["non_scheduled", Reserve.where(reserved_date: date, reserved_space: space)]
        end
      logger.debug("============ date = #{date} space = #{space} result = #{result[0]} ... #{result[1]}")
      return result

    end
    
# -------- 2023/08/23 add for new アルゴリズム by matsushita ------------------ start
    
    def new_reserve_availability_20230824(machine, staff, date, space)
      
      logger.debug("================= 20230824 machine=#{machine} staff=#{staff} date=#{date} space=#{space} ")
      
      # 既にその枠に予約があれば
      reserved_infos = Reserve.where(reserved_date: date, reserved_space: space)

      # そのmachineを使えるスタッフarr
      can_staffs_arr = StaffMachineRelation.where(machine: machine).where.not(staff_id: 0).pluck(:staff_id)
      
      # その枠に出勤スタッフarr取得
      attendances_arr = Schedule.where(schedule_date: date, schedule_space: space, staff_id: can_staffs_arr).pluck(:staff_id)
      
      # その枠で該当スタッフの予約
      reserved_of_staff = Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: staff.id)
      
      
      if machine == "h" || machine == "w"
        
        # 新規客対応可能スタッフ配列
        new_customer_able_staffs_arr = Staff.where(new_customer_flag: true, dismiss_flag: false, active_flag: true).pluck(:id)
        attendances_arr_of_new_customer = attendances_arr & new_customer_able_staffs_arr # 重複を取得
        # logger.debug("~~~~~~~~~~~~~~~~~~~ attendances_arr_of_new_customer = #{attendances_arr_of_new_customer}") 
        # 新規対応不可スタッフ配列
        new_customer_unable_staffs_arr = Staff.where(new_customer_flag: false, dismiss_flag: false, active_flag: true).pluck(:id)
        attendances_arr_of_unable_new_customer = attendances_arr & new_customer_unable_staffs_arr # 重複を取得
        
     
        # 稼働machine 台数取得
        holistic_numbers = Machine.find_by(short_word: "h").number_of_machine # wellbeing_numbers = Machine.find_by(short_word: "w").number_of_machine
        number_of_holistic = holistic_numbers - machine_schedule(date, space, "h")
        # logger.debug("~~~~~~~~~~~~~~~~~~~ number_of_holistic = #{number_of_holistic}") 
        # 新規客予約数
        num_of_reseve_for_new = Reserve.where(reserved_date: date, reserved_space: space, new_customer: true).count
        # logger.debug("~~~~~~~~~~~~~~~~~~~ num_of_reseve_for_new = #{num_of_reseve_for_new}") 
        # 既存客予約数
        num_of_reseve_for_old = Reserve.where(reserved_date: date, reserved_space: space, new_customer: false).count
        # logger.debug("~~~~~~~~~~~~~~~~~~~ num_of_reseve_for_old = #{num_of_reseve_for_old}") 
        
        
        # 例　value = [0,1] <= 新規カレンダー表示は0で✖️　既存カレンダーは1で△
        if value = reserve_algorithms_hash[[attendances_arr_of_new_customer.size, attendances_arr_of_unable_new_customer.size, number_of_holistic, num_of_reseve_for_new, num_of_reseve_for_old]]
            if user_signed_in?
              # 既存顧客と管理者
              result = [value[1], reserved_infos]
            else
              # 新規顧客
              result = [value[0], reserved_infos]
            end
            # logger.debug("~~~~~~~~~~~~~~~~~~~ result not error = #{result}")        
        else
            # logger.debug("~~~~~~~~~~~~~~~~~~~ result error value = #{value}") 
          # 該当ないのErrorなので,予約不可にする
            result = [-1,reserved_infos]
            # logger.debug("~~~~~~~~~~~~~~~~~~~ result error = #{result}")          
        end
      else
        if machine == "e" || (machine == "o" && staff.id == StaffMachineRelation.body_staff_id) # エステか成美か　（今後成美以外のエステスタッフが増えればif分に追加必要）
                
            # エステスタッフで出勤している人配列 -> attendances_arr
            if !attendances_arr.include?(staff.id)
              # スタッフが出勤していないなら
                result = [-1, reserved_infos]
            else 
                # 
                if Reserve.find_by(reserved_date: date, reserved_space: space, machine: "e") || Reserve.find_by(reserved_date: date, reserved_space: space, machine: "o", staff_id: StaffMachineRelation.esute_staff_id)
                  # エステの予約入っているなら
                   result = [0, reserved_infos]  # ✖️
                else
                  # 当該スタッフの予約入ってないなら
                   result = [1, reserved_infos]  # △
                end
            end          
        elsif machine == "b" || (machine == "o" && staff.id == StaffMachineRelation.body_staff_id) # 鍼・整体かスタッフか
            if !attendances_arr.include?(staff.id)
              # 当該スタッフ出勤していないなら
                result = [-1, reserved_infos] # ==
            else 
                if Reserve.find_by(reserved_date: date, reserved_space: space, machine: "b") || Reserve.find_by(reserved_date: date, reserved_space: space, machine: "o", staff_id: 8)
                  # 鍼・整体の予約入っているなら
                  result = [0, reserved_infos]  # ✖️
                else
                  # 当該スタッフの予約入ってないなら
                  result = [1, reserved_infos]  # △
                end
            end
        elsif machine == "s" || (machine == "o" && staff.id == 1) # 算命学 鹿田がavailableかどうかの判断が必要
            if !attendances_arr.include?(staff.id)
              # 当該スタッフ出勤していないなら
                result = [-1, reserved_infos] # ==
            else 
                if reserved_of_staff
                  # 当該スタッフの予約入っているなら
                  result = [0, reserved_infos]  # ✖️
                else
                  # 当該スタッフの予約入ってないなら
                  result = [1, reserved_infos]  # △
                end
            end
        else # error
            if !attendances_arr.include?(staff.id)
              # 当該スタッフ出勤していないなら
                result = [-1, reserved_infos] # ==
            else 
                if reserved_of_staff
                  # 当該スタッフの予約入っているなら
                  result = [0, reserved_infos]  # ✖️
                else
                  # 当該スタッフの予約入ってないなら
                  result = [1, reserved_infos]  # △
                end
            end
        end  # メタトロン以外の予約アルゴリズム end 

      end  # 全アルゴリズム end
      
      return result
      
    end    # def end
    
    # 2023/08/24 朝6:30 ここまで 次はメタトロン以外の整体、算命学 の分岐　あとはhtmlへ送るデータとhtmlの修正するかどうか
    
# -------- 2023/08/23 add for new アルゴリズム by matsushita ------------------  end

    
    def new_reserve_availability_20220812(machine, staff, date, space)
      
        logger.debug("^^^^^^^^^^^^^^^^^^^^^ MachineSchedule = #{machine_schedule(date, space, machine)}")
        reserved_infos = Reserve.where(reserved_date: date, reserved_space: space)

      
        wellbeing_numbers = Machine.find_by(short_word: "w").number_of_machine
        holistic_numbers = Machine.find_by(short_word: "h").number_of_machine

        machine_numbers_hash = {"w" =>  (wellbeing_numbers-machine_schedule(date, space, "w")), "h" => (holistic_numbers-machine_schedule(date, space, "h"))}
        logger.debug("========================= machine_numbers_hash = #{machine_numbers_hash}")
        vacant_wellbeing = machine_numbers_hash["w"] - Reserve.where(reserved_date: date, reserved_space: space, machine: "w").count
        vacant_holistic = machine_numbers_hash["h"] - Reserve.where(reserved_date: date, reserved_space: space, machine: "h").count
        # そのmachineを使えるスタッフarr
        can_staffs_arr = StaffMachineRelation.where(machine: machine).where.not(staff_id: 0).pluck(:staff_id)
        # その枠にそのmachineを使える出勤しているスタッフarr
        attendances_arr = Schedule.where(schedule_date: date, schedule_space: space, staff_id: can_staffs_arr).pluck(:staff_id)
        # 指名なし予約数
        non_nominated_reserve_count = Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0).count
        # その枠に予約済みにスタッフ
        reserved_staffs_arr = Reserve.where(reserved_date: date, reserved_space: space, staff_id: attendances_arr).pluck(:staff_id)

        # vacant_staffs_arr は 空いてるスタッフidの配列(鹿田は2人として計算している)
        if attendances_arr.include?(1) 
          # 鹿田出勤している
            if machine == "o" && staff.id == 1
              logger.debug("================ sannmei Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0).count = #{Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0 ).count}")
              # 算命学の予約可能か
              if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1)
                # その枠に鹿田の予約が何かしら入っていたら
                vacant_staffs_arr = attendances_arr - [1]
              elsif (non_nominated_reserve_count === attendances_arr.count)
                # その枠に鹿田の予約が何かしら入ってなかったら
                vacant_staffs_arr = []
              else
                vacant_staffs_arr = attendances_arr
              end
            else
              if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "o")
                # 算命学が予約入っていた場合
                vacant_staffs_arr = attendances_arr - [1] - reserved_staffs_arr
              elsif (masako_available_count(date, space, machine) == 2)
                # 算命学予約入っていなく、鹿田のh,wの予約入ってない場合
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr + [1]
              elsif (masako_available_count(date, space, machine) == 1)
                # 算命学予約入ってなくて,鹿田のh,wの予約が1つ入っている
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr + [1]
              elsif (masako_available_count(date, space, machine) == 0)
                # 算命学予約入ってなくて,鹿田のh,wの予約が2つ入っている
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr
              else
                vacant_staffs_arr = attendances_arr - reserved_staffs_arr
              end
            end
        else # 鹿田が出勤してない場合
          vacant_staffs_arr = attendances_arr - reserved_staffs_arr
        end
        
      
    
        if attendances_arr.present?  
            # 施術可能スタッフ出勤していたら
            if machine == "h"
              if staff.id == 0 # 指名なし
                logger.debug("======================== space = #{space} holistic 指名なし reserved_infos.count = #{reserved_infos.count} vacant_holistic = #{vacant_holistic} vacant_staffs_arr = #{vacant_staffs_arr}")
                if (attendances_arr-[1]).count == 0
                  # 下記に修正 2023/3/10
                  available_count = [vacant_holistic, masako_available_count(date, space, machine)+(attendances_arr-[1]).count].sort[0]
                  # available_count = [vacant_holistic, masako_available_count(date, space, machine)+(attendances_arr-[1]).count-reserved_staffs_arr.count].sort[0]
                  logger.debug("~~~~~~~~~~~~~~~~~~~~~ (attendances_arr-[1]).count == 0 masako_available_count(date, space, machine)+(attendances_arr-[1]).count-reserved_staffs_arr.count = #{masako_available_count(date, space, machine)+(attendances_arr-[1]).count-reserved_staffs_arr.count}")
                else
                  available_count = [vacant_holistic, masako_available_count(date, space, machine)+(attendances_arr-[1]).count-reserved_staffs_arr.count-non_nominated_reserve_count].sort[0]
                  logger.debug("~~~~~~~~~~~~~~~~~~~~~ (attendances_arr-[1]).count != 0")
                end
                vacant_holistic_nonominated = available_count
                logger.debug("~~~~~~~~~~~~~~~~~ masako_available_count = #{masako_available_count(date, space, machine)}  vacant_holistic = #{vacant_holistic} available_count = #{available_count} attendances_arr = #{attendances_arr}")

                    if vacant_holistic_nonominated == 2  # machine2台空きある
                      if vacant_staffs_arr.count >= 2  # スタッフ2人空きある
                        result = ["reservable_two", reserved_infos]   # ◎ 
                      elsif vacant_staffs_arr.count == 1 #スタッフ1人空きがある
                        result = ["reservable_one", reserved_infos]  # △
                        logger.debug("======================== holistic 指名なし reservable_one reserved_infos count = #{reserved_infos.count}}}")
                      else  #スタッフ空きなし
                        result = ["reserved", reserved_infos]  # ✖️
                        logger.debug("======================== holistic 指名なし reserved }")
                      end
                      # result = ["non_scheduled", reserved_infos]
                    elsif  vacant_holistic_nonominated == 1  # machine1台空きある
                      if vacant_staffs_arr.count >= 1  # スタッフ1人以上空きある
                        if can_staffs_arr.include?(1)
                          can_do_staff_number = attendances_arr.count + 1
                          all_reserve_count = Reserve.where(reserved_date: date, reserved_space: space, machine: ["h"]).count
                          if (can_do_staff_number - all_reserve_count) >= 1
                             logger.debug("======================== (can_do_staff_number(#{can_do_staff_number}) - all_reserve_count(#{all_reserve_count}})) >= 1 vacant_staffs_arr = #{vacant_staffs_arr}}}")
                             result = ["reservable_one", reserved_infos]  # △
                          else
                             logger.debug("======================== (can_do_staff_number(#{can_do_staff_number}) - all_reserve_count(#{all_reserve_count}})) < 1}")
                            result = ["reserved", reserved_infos]  # ✖️
                          end
                        else
                        end
                      else #スタッフ空きなし
                        logger.debug("================== スタッフ空きなし")
                        result = ["reserved", reserved_infos]  # ✖️
                      end          
                    else 
                      # machine空きなし
                      logger.debug("================== machine空きなし vacant_holistic_nonominated =#{vacant_holistic_nonominated} vacant_holistic = #{vacant_holistic} masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                      result = ["reserved", reserved_infos]  # ✖️
                    end
              else 
              # 指名あり
                # 指名スタッフ出勤している
                if attendances_arr.include?(staff.id)
                  
                      if staff.id != 1 # 指名が鹿田でないなら
                      
                        if vacant_holistic >= 2  # machine2台以上空きある
                        
                          if vacant_staffs_arr.include?(1) && !staff.id == 1  # 鹿田空いてる
                            if masako_available_count(date, space, machine) >= 2
                              result = ["reservable_two", reserved_infos]   # ◎ 
                            elsif masako_available_count(date, space, machine) == 1
                              result = ["reservable_one", reserved_infos]  # △
                            else
                              result = ["reserved", reserved_infos]  # ✖️
                            end
                            
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id == 1  # スタッフ空きある
                            result = ["reservable_two", reserved_infos]   # ◎ 
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id != 1  # スタッフ空きある
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end 
                          
                        elsif vacant_holistic == 1  # machine1台空きある
                          if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                           logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end         
                        else # machine空きなし
                          result = ["reserved", reserved_infos]  # ✖️
                        end
                        
                      else
                        # 鹿田なら
                        if vacant_holistic >= 2 && (masako_available_count(date, space, machine) >= 2)  # machine2台以上空きある
                        
                          if vacant_staffs_arr.include?(1) && !staff.id == 1  # 鹿田空いてる
                            if masako_available_count(date, space, machine) >= 2
                              result = ["reservable_two", reserved_infos]   # ◎ 
                            elsif masako_available_count(date, space, machine) == 1
                              result = ["reservable_one", reserved_infos]  # △
                            else
                              result = ["reserved", reserved_infos]  # ✖️
                            end
                            
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id == 1  # スタッフ空きある
                            result = ["reservable_two", reserved_infos]   # ◎ 
                          elsif vacant_staffs_arr.include?(staff.id) && staff.id != 1  # スタッフ空きある
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end 
                          
                        elsif vacant_holistic == 2 && (masako_available_count(date, space, machine) >= 1)  # machine1台空き��る
                          if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                           logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end                          
                        elsif vacant_holistic == 1 && (masako_available_count(date, space, machine) >= 1)  # machine1台空きある
                          if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                           logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}")
                            result = ["reservable_one", reserved_infos]  # △
                          else  #スタッフ空きなし
                            result = ["reserved", reserved_infos]  # ✖️
                          end
                        else
                          # machine空きなし
                          logger.debug("~~~~~~~~~~~~~~~~~~~~ 指名あり 439 vacant_holistic == #{vacant_holistic} && (masako_available_count(date, space, machine) = #{masako_available_count(date, space, machine)}})")
                          result = ["reserved", reserved_infos]  # ✖️
                        end  
                      end
                else
                  # 指名スタッフ出勤していない
                  result = ["non_scheduled", reserved_infos]
                end
              end
            elsif machine == "w"
              if staff.id == 0 # 指名なし
                if vacant_wellbeing == 2  # machine2台空きある
                  if vacant_staffs_arr >= 2  # スタッフ2人空きある
                    result = ["reservable_two", reserved_infos]   # ◎ 
                  elsif vacant_staffs_arr.count == 1 #スタッフ1人空きがある
                    result = ["reservable_one", reserved_infos]  # △
                  else  #スタッフ空きなし
                    result = ["reserved", reserved_infos]  # ✖️
                  end
                elsif vacant_wellbeing == 1  # machine1台空きある
                  if vacant_staffs_arr.count >= 1  # スタッフ1人以上空きある
                    result = ["reservable_one", reserved_infos]  # △
                  else #スタッフ空きなし
                    result = ["reserved", reserved_infos]  # ✖️
                  end          
                else # machine空きなし
                  result = ["non_scheduled", reserved_infos]  # ==
                end
              else 
                # 指名あり
                # 指名スタッフ出勤している
                  if attendances_arr.include?(staff.id)
                      if vacant_wellbeing >= 1  # machine1台以上空きある
                        if vacant_staffs_arr.include?(staff.id)  # スタッフ空きある
                          result = ["reservable_one", reserved_infos]  # △
                        else  #スタッフ空きなし
                          result = ["reserved", reserved_infos]  # ✖️
                        end         
                      else # machine空きなし
                        result = ["reserved", reserved_infos]  # ✖️
                      end
                  else
                    # 指名スタッフ出勤していない
                    result = ["non_scheduled", reserved_infos]
                  end
                      
              end
            elsif machine == "o" && staff.id == 1     # 算命学
               logger.debug("~~~~~~~~~~~~~~~~~~~~~~ masako_available_count(date, space, machine) #{masako_available_count(date, space, machine)}")
               if !attendances_arr.include?(1)
                # 鹿田出勤してないなら
                  result = ["non_scheduled", reserved_infos]
               else
                # 鹿田出勤してる
                  logger.debug("||||===================  machine = o , reserved_infos.count = #{reserved_infos.count} vacant_staffs_arr = #{vacant_staffs_arr}in helper ")
                  if vacant_staffs_arr.include?(1)
                    if masako_available_count(date, space, machine) >= 1
                      # 鹿田の予約入ってないなら
                      result = ["reservable_one", reserved_infos]  # △                      
                    # 鹿田が稼働しているなら
                    # masako_reserved = Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1)
                    else
                      logger.debug("||||=================== 1")
                      result = ["reserved", reserved_infos]  # ✖️
                    end
                  else
                    logger.debug("||||=================== 2")
                    result = ["reserved", reserved_infos]  # ✖️
                  end
              end
            
            elsif machine == "o" && staff.id == 5 # (夏子腸もみ・ファスティング)
                if !attendances_arr.include?(5)
                  # 夏子出勤していないなら
                    result = ["non_scheduled", reserved_infos]
                else 
                    if !vacant_staffs_arr.include?(5)
                      # 夏子予約入っているなら
                       result = ["reserved", reserved_infos]  # ✖️
                    else
                      # 夏子の予約入ってないなら
                       result = ["reservable_one", reserved_infos]  # △
                    end
                end
              
            elsif machine == "o" && staff.id == 8 # 佐藤
                if !attendances_arr.include?(8)
                  # 佐藤出勤していないなら
                    result = ["non_scheduled", reserved_infos]
                else 
                    if !vacant_staffs_arr.include?(8)
                      # 佐藤予約入っているなら
                       result = ["reserved", reserved_infos]  # ✖️
                    else
                      # 佐藤の予約入ってないなら
                       result = ["reservable_one", reserved_infos]  # △
                    end
                end
            else 
              # その他のその他スタッフ
                if !attendances_arr.include?(staff.id)
                  # 出勤していないな���
                    result = ["non_scheduled", reserved_infos]
                else 
                    if !vacant_staffs_arr.include?(staff.id)
                      # 予約入っているなら
                       result = ["reserved", reserved_infos]  # ✖️
                    else
                      # 予約入ってないなら
                       result = ["reservable_one", reserved_infos]  # △
                    end
                end        
            end
        else
          # 施術可能スタッフ出勤してない
          result = ["non_scheduled", Reserve.where(reserved_date: date, reserved_space: space)]
        end
      logger.debug("============ date = #{date} space = #{space} result = #{result[0]} ... #{result[1]}")
      return result

    end
    
  
    
    
    
    private
      def masako_available_count(date, space, machine)
        
        # 出勤しているスタッフarr
        attendances_arr = Schedule.where(schedule_date: date, schedule_space: space).pluck(:staff_id)
        # その枠でそのmachineを使える出勤しているスタッフ
        can_staffs_arr = StaffMachineRelation.where(staff_id: attendances_arr, machine: machine).pluck(:staff_id)
        # その枠に予約済みにスタッフ
        reserved_staffs_arr = Reserve.where(reserved_date: date, reserved_space: space).pluck(:staff_id)        
        # その枠に空いてる鹿田以外のそのマシンを使えるスタッフ
        vacant_staffs_without_masako_arr = can_staffs_arr - reserved_staffs_arr - [1]
        # 指名なしの予約数
        reserve_nonnominated = Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0, machine: ["h","w"])

        
        
        if !Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: 1)
          # 鹿田出勤してない
          availabilities = 0
        else
          # 鹿田出勤している
          can_staffs_arr = can_staffs_arr + [1]
          if Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "o")
            # 算命学の予約入っている
            availabilities = 0
          elsif Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "h", new_customer: true)
            # 新規のお客様の予約が入っている(new_costmer) 2023/08/08
            availabilities = 0
          elsif Reserve.where(reserved_date: date, reserved_space: space, staff_id: 1, machine: ["h","w"]).count >= 2
            # 算命学以外の鹿田予約が2件入っている
            availabilities = 0
          elsif Reserve.where(reserved_date: date, reserved_space: space, staff_id: 1, machine: ["h","w"]).count == 1
            # 算命学以外の鹿田予約が1件入っている
            if Reserve.where(reserved_date: date, reserved_space: space, staff_id: 0, machine: ["h","w"]).count == 0
              # 指名なし予約が入ってない
              availabilities = 1
            else
              # 鹿田以外の空いてるスタッフ数と指名なし予約数が同じ以上なら
              logger.debug("~~~~~~~~~~~~~~~~~ vacant_staffs_without_masako_arr = #{vacant_staffs_without_masako_arr} reserve_nonnominated.count = #{reserve_nonnominated.count}")
              if (can_staffs_arr.count - 1- reserve_nonnominated.count) >= 1
                logger.debug("~~~~~~~~~~~~~~~~~~~~~~~ ここ1")
                availabilities = 1
              else
                logger.debug("~~~~~~~~~~~~~~~~~~~~~~~ ここ2")
                availabilities = 0
              end
            end
          else
            # 鹿田のhやWの予約が１件も入っていない
            # 算命学以外の鹿田の予約も全く入ってない
            # 鹿田以外の空いてるスタッフ数と指名なし予約数が同じ以上なら
            logger.debug("~~~~~~~~~~~~~~~~~~~~~~~~~~ vacant_staffs_without_masako_arr = #{vacant_staffs_without_masako_arr} reserve_nonnominated.count = #{reserve_nonnominated.count}")
            logger.debug("~~~~~ vacant_staffs_without_masako_arr.length + 2 - reserve_nonnominated.count = #{vacant_staffs_without_masako_arr.length + 2 - reserve_nonnominated.count}")
            if (vacant_staffs_without_masako_arr.length + 2 - reserve_nonnominated.count) >= 2
                availabilities = 2
                logger.debug("----^^^^^^^^^^^^^^^ availabilities = #{availabilities} vacant_staffs_without_masako_arr = #{vacant_staffs_without_masako_arr} reserve_nonnominated = #{reserve_nonnominated.count} ")
            elsif (vacant_staffs_without_masako_arr.length + 2 - reserve_nonnominated.count) == 1
                availabilities = 1
            else
                availabilities = 0
            end 

          end
        end
        logger.debug("¥¥¥¥¥¥¥¥¥ availabilities = #{availabilities}")
        return availabilities
      end
      
      
      def machine_schedule(date, space, machine)
        if MachineSchedule.find_by(machine_schedule_date: date, machine_schedule_space: space, machine: machine)
          return 1
        else
          return 0
        end
      end
      
      def reserve_algorithms_array
        # arr = [[[1, 0, 2, 0, 0], [1, 1]],.......]
        arr = []
        ReserveAlgorithm.all.each do |ra|
            arr << [[ra.num_staffs_for_new, ra.num_staffs_for_nonnew, ra.num_of_machines, ra.num_of_reseve_for_new, ra.num_of_reseve_for_old],[ra.available_for_new, ra.available_for_old]]
        end
        logger.debug("ReserveAlgorithm arr = #{arr}")
        return arr
      end

      def reserve_algorithms_hash
        # hash = {[1, 0, 2, 0, 0] => [1, 1], [1, 0, 2, 0, 1] => [1, 2],......}
        hash = {}
        ReserveAlgorithm.all.each do |ra|
            hash.store([ra.num_staffs_for_new, ra.num_staffs_for_nonnew, ra.num_of_machines, ra.num_of_reseve_for_new, ra.num_of_reseve_for_old], [ra.available_for_new, ra.available_for_old])
        end
        # logger.debug("ReserveAlgorithm hash = #{hash}")
        return hash
      end
    
end
