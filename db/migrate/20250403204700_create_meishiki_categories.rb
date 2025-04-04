class CreateMeishikiCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :meishiki_categories do |t|
        t.string "name"
        t.timestamps
    end
  end
end
