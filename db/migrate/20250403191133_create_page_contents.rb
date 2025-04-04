class CreatePageContents < ActiveRecord::Migration[8.0]
  def change
    create_table :page_contents do |t|
      t.text "content"
      t.integer "user_type_id"
      t.timestamps
    end
  end
end
