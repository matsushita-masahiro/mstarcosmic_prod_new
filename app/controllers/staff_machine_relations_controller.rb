class StaffMachineRelationsController < ApplicationController
    
    # before_action :get_staff
    
    
    def update
        if staff_machine_relation_params[:staff_id].present?
        
          save_flag = false
          
          StaffMachineRelation.where(staff_id: staff_machine_relation_params[:staff_id]).delete_all
          staff_machine_relation_params[:machine].each do |machine|
  
              if StaffMachineRelation.create(staff_id: staff_machine_relation_params[:staff_id], machine: machine)
                  save_flag = true
              else
                  save_flag = false
              end              
  
          end # each end
          
          if save_flag 
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
      
end
