class AddAboFlagToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :abo_flag, :boolean, default: false, null: false
  end
end
