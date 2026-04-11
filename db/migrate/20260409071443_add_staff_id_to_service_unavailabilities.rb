class AddStaffIdToServiceUnavailabilities < ActiveRecord::Migration[8.0]
  def change
    add_column :service_unavailabilities, :staff_id, :integer, default: 1
  end
end
