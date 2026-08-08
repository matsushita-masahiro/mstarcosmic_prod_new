class CreateTreatmentNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :treatment_notes do |t|
      t.references :user, null: false, foreign_key: true
      # 担当スタッフ。User が消えても記録は残すため nullify（名前は author_name に控える）
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :author_name, null: false
      t.date   :visited_on,  null: false
      t.text   :body
      t.string :ticket
      t.timestamps
    end
    add_index :treatment_notes, %i[user_id visited_on]
  end
end
