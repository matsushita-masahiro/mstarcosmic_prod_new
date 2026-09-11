class CreateQuestionnaireAnnotations < ActiveRecord::Migration[8.0]
  def change
    create_table :questionnaire_annotations do |t|
      t.references :medical_questionnaire, null: false, foreign_key: true
      t.string  :question_key, null: false
      t.text    :body,         null: false
      # 既存の medical_questionnaires.reviewed_by_id と同じ流儀で users を指す。
      t.references :staff, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    # 設問ごとに引くための索引。カルテは版の連なりぶんをまとめて読む。
    add_index :questionnaire_annotations, [ :medical_questionnaire_id, :question_key ],
              name: "idx_annotations_on_questionnaire_and_question"
  end
end
