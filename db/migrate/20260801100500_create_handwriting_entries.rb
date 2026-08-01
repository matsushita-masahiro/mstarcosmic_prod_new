class CreateHandwritingEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :handwriting_entries do |t|
      t.references :medical_questionnaire, null: false, foreign_key: true,
                   index: { name: "idx_handwriting_on_questionnaire" }
      t.string :question_key, null: false
      t.jsonb :strokes, null: false, default: []
      t.integer :canvas_width
      t.integer :canvas_height
      t.text :transcribed_text
      t.timestamps
    end
    add_index :handwriting_entries, %i[medical_questionnaire_id question_key],
              unique: true, name: "idx_handwriting_unique_per_question"
  end
end
