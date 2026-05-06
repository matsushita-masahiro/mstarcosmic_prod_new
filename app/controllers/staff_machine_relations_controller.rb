class StaffMachineRelationsController < ApplicationController
    
    # before_action :get_staff
    
    
    def update
        if staff_machine_relation_params[:staff_id].present?
        
          save_flag = false
          staff_id = staff_machine_relation_params[:staff_id]
          
          StaffMachineRelation.where(staff_id: staff_id).delete_all
          staff_machine_relation_params[:machine].each do |machine|
  
              if StaffMachineRelation.create(staff_id: staff_id, machine: machine)
                  save_flag = true
              else
                  save_flag = false
              end              
  
          end # each end
          
          if save_flag 
              # staff_servicesも同期
              sync_staff_services(staff_id, staff_machine_relation_params[:machine])
              flash[:notice] = "担当マシン修正しました"
          else
              flash[:alert] = "修正できませんでした"
          end
        else
          flash[:alert] = "スタッフが選択されていません"
        end
        redirect_to "/admin/staffs/new"
    end
    
    private 
      def staff_machine_relation_params
          params.require(:staff_machine_relation).permit(:staff_id, machine: [])
      end

      def sync_staff_services(staff_id, machines)
        # machineからservice名へのマッピング
        services = machines.map { |m| machine_to_service(m) }.uniq

        # 既存のstaff_servicesを削除して再作成
        StaffService.where(staff_id: staff_id).delete_all
        services.each do |service_name|
          StaffService.create(staff_id: staff_id, service: service_name)
        end
      end

      def machine_to_service(machine)
        case machine
        when 'h', 'stem', 'w'
          'holistic'
        when 'e'
          'esute'
        else
          'seitai'
        end
      end
      
end
