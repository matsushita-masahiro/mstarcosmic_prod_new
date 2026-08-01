class CreateBodyMarks < ActiveRecord::Migration[8.0]
  def change
    create_table :body_marks do |t|
      t.references :medical_questionnaire, null: false, foreign_key: true,
                   index: { name: "idx_body_marks_on_questionnaire" }
      t.integer :side, null: false
      t.decimal :x, precision: 5, scale: 4, null: false
      t.decimal :y, precision: 5, scale: 4, null: false
      t.integer :mark_type, null: false, default: 0
      t.integer :severity
      t.string  :note
      t.timestamps
    end
    add_index :body_marks, :side
  end
end
