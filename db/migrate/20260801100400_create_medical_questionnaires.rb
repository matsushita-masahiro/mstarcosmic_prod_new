class CreateMedicalQuestionnaires < ActiveRecord::Migration[8.0]
  def change
    create_table :medical_questionnaires do |t|
      t.references :user,           null: false, foreign_key: true
      t.references :intake_session, foreign_key: true
      t.string :form_version, null: false, default: "2026-04-17"
      t.jsonb :answers, null: false, default: {}
      t.boolean :has_pacemaker,        null: false, default: false
      t.boolean :has_implanted_device, null: false, default: false
      t.boolean :is_pregnant,          null: false, default: false
      t.integer :pregnancy_weeks
      t.boolean :pregnancy_unknown,    null: false, default: false
      t.boolean :is_breastfeeding,     null: false, default: false
      t.boolean :under_treatment,      null: false, default: false
      t.boolean :taking_medication,    null: false, default: false
      t.integer  :status, null: false, default: 0
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :medical_questionnaires, :answers, using: :gin
    add_index :medical_questionnaires, %i[user_id submitted_at]
    add_index :medical_questionnaires, :has_pacemaker
    add_index :medical_questionnaires, :is_pregnant
  end
end
