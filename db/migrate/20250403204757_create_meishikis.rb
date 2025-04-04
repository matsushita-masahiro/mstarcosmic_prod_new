class CreateMeishikis < ActiveRecord::Migration[8.0]
  def change
    create_table :meishikis do |t|
      t.string "name"
      t.string "meishiki"
      t.integer "meishiki_category_id"      
      t.timestamps
    end
  end
end
