# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_02_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "answers", force: :cascade do |t|
    t.integer "inquiry_id"
    t.integer "user_id"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "body_marks", force: :cascade do |t|
    t.bigint "medical_questionnaire_id", null: false
    t.integer "side", null: false
    t.decimal "x", precision: 5, scale: 4, null: false
    t.decimal "y", precision: 5, scale: 4, null: false
    t.integer "mark_type", default: 0, null: false
    t.integer "severity"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["medical_questionnaire_id"], name: "idx_body_marks_on_questionnaire"
    t.index ["side"], name: "index_body_marks_on_side"
  end

  create_table "consent_documents", force: :cascade do |t|
    t.string "version", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "body_digest", null: false
    t.datetime "published_at"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_consent_documents_on_published_at"
    t.index ["version"], name: "index_consent_documents_on_version", unique: true
  end

  create_table "consents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "consent_document_id", null: false
    t.bigint "intake_session_id"
    t.datetime "agreed_at", null: false
    t.string "signer_name"
    t.integer "signer_relation", default: 0
    t.jsonb "signature_strokes"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agreed_at"], name: "index_consents_on_agreed_at"
    t.index ["consent_document_id"], name: "index_consents_on_consent_document_id"
    t.index ["intake_session_id"], name: "index_consents_on_intake_session_id"
    t.index ["user_id", "consent_document_id"], name: "index_consents_on_user_id_and_consent_document_id"
    t.index ["user_id"], name: "index_consents_on_user_id"
  end

  create_table "coupons", force: :cascade do |t|
    t.integer "payment_id"
    t.string "status"
    t.integer "order_number"
    t.string "remarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "handwriting_entries", force: :cascade do |t|
    t.bigint "medical_questionnaire_id", null: false
    t.string "question_key", null: false
    t.jsonb "strokes", default: [], null: false
    t.integer "canvas_width"
    t.integer "canvas_height"
    t.text "transcribed_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "input_mode", default: 0, null: false
    t.index ["medical_questionnaire_id", "question_key"], name: "idx_handwriting_unique_per_question", unique: true
    t.index ["medical_questionnaire_id"], name: "idx_handwriting_on_questionnaire"
  end

  create_table "inquiries", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "intake_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "issuer_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "completed_at"
    t.datetime "revoked_at"
    t.string "issuer_ip"
    t.string "client_ip"
    t.string "client_user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_intake_sessions_on_expires_at"
    t.index ["issuer_id"], name: "index_intake_sessions_on_issuer_id"
    t.index ["token_digest"], name: "index_intake_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_intake_sessions_on_user_id"
  end

  create_table "karte_access_logs", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.bigint "patient_id", null: false
    t.string "action", null: false
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.index ["actor_id", "created_at"], name: "index_karte_access_logs_on_actor_id_and_created_at"
    t.index ["actor_id"], name: "index_karte_access_logs_on_actor_id"
    t.index ["patient_id", "created_at"], name: "index_karte_access_logs_on_patient_id_and_created_at"
    t.index ["patient_id"], name: "index_karte_access_logs_on_patient_id"
  end

  create_table "machine_schedules", force: :cascade do |t|
    t.date "machine_schedule_date"
    t.float "machine_schedule_space"
    t.string "machine"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "staff_id"
  end

  create_table "machines", force: :cascade do |t|
    t.string "name"
    t.integer "number_of_machine"
    t.string "short_word"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "medical_questionnaires", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "intake_session_id"
    t.string "form_version", default: "2026-04-17", null: false
    t.jsonb "answers", default: {}, null: false
    t.boolean "has_pacemaker", default: false, null: false
    t.boolean "has_implanted_device", default: false, null: false
    t.boolean "is_pregnant", default: false, null: false
    t.integer "pregnancy_weeks"
    t.boolean "pregnancy_unknown", default: false, null: false
    t.boolean "is_breastfeeding", default: false, null: false
    t.boolean "under_treatment", default: false, null: false
    t.boolean "taking_medication", default: false, null: false
    t.integer "status", default: 0, null: false
    t.datetime "submitted_at"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["answers"], name: "index_medical_questionnaires_on_answers", using: :gin
    t.index ["has_pacemaker"], name: "index_medical_questionnaires_on_has_pacemaker"
    t.index ["intake_session_id"], name: "index_medical_questionnaires_on_intake_session_id"
    t.index ["is_pregnant"], name: "index_medical_questionnaires_on_is_pregnant"
    t.index ["reviewed_by_id"], name: "index_medical_questionnaires_on_reviewed_by_id"
    t.index ["user_id", "submitted_at"], name: "index_medical_questionnaires_on_user_id_and_submitted_at"
    t.index ["user_id"], name: "index_medical_questionnaires_on_user_id"
  end

  create_table "metatron_sale_inquiries", force: :cascade do |t|
    t.string "name"
    t.string "name_kana"
    t.string "phone"
    t.string "email"
    t.integer "postcode"
    t.integer "prefecture_code"
    t.string "address_city"
    t.boolean "trial_flag", default: false, null: false
    t.boolean "buy_consult_flag", default: false, null: false
    t.boolean "hp_consult_flag", default: false, null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ms_inquiry_answers", force: :cascade do |t|
    t.integer "metatron_sale_inquiry_id"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metatron_sale_inquiry_id"], name: "index_ms_inquiry_answers_on_metatron_sale_inquiry_id"
  end

  create_table "page_contents", force: :cascade do |t|
    t.text "content"
    t.integer "user_type_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "patient_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name_kana"
    t.string "name_roman"
    t.date "birth_date"
    t.integer "sex"
    t.integer "blood_type"
    t.string "postal_code"
    t.string "prefecture"
    t.string "city"
    t.string "address_line"
    t.string "building"
    t.string "phone"
    t.string "nearest_station"
    t.integer "referral_source"
    t.string "referral_detail"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name_kana"], name: "index_patient_profiles_on_name_kana"
    t.index ["postal_code"], name: "index_patient_profiles_on_postal_code"
    t.index ["user_id"], name: "index_patient_profiles_on_user_id", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.integer "user_id"
    t.integer "price"
    t.string "pay_type"
    t.text "remarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "staff_id"
    t.string "service", limit: 20, null: false
    t.date "date", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.integer "duration", null: false
    t.boolean "is_new_customer", default: false, null: false
    t.text "notes"
    t.integer "status", default: 0, null: false
    t.string "group_id", limit: 36
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_reservations_on_date"
    t.index ["staff_id", "date"], name: "index_reservations_on_staff_id_and_date"
    t.index ["user_id"], name: "index_reservations_on_user_id"
  end

  create_table "reserve_algorithms", force: :cascade do |t|
    t.integer "num_staffs_for_new"
    t.integer "num_staffs_for_nonnew"
    t.integer "num_of_machines"
    t.integer "num_of_reseve_for_new"
    t.integer "num_of_reseve_for_old"
    t.integer "available_for_new"
    t.integer "available_for_old"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reserves", force: :cascade do |t|
    t.integer "user_id"
    t.date "reserved_date"
    t.text "remarks"
    t.float "reserved_space"
    t.integer "root_reserve_id"
    t.integer "staff_id"
    t.string "machine"
    t.boolean "new_customer", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "schedules", force: :cascade do |t|
    t.integer "user_id"
    t.date "schedule_date"
    t.float "schedule_space"
    t.string "schedule_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "staff_id"
    t.index ["staff_id"], name: "index_schedules_on_staff_id"
    t.index ["user_id"], name: "index_schedules_on_user_id"
  end

  create_table "service_unavailabilities", force: :cascade do |t|
    t.string "service", limit: 20, null: false
    t.date "date", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.string "reason", limit: 50, default: "business_trip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "staff_id", default: 1
    t.index ["date"], name: "index_service_unavailabilities_on_date"
    t.index ["service", "date"], name: "index_service_unavailabilities_on_service_and_date"
  end

  create_table "services", force: :cascade do |t|
    t.string "name", limit: 50, null: false
    t.string "display_name", limit: 50, null: false
    t.integer "max_concurrent", default: 1, null: false
    t.integer "min_duration", default: 30, null: false
    t.integer "max_duration", default: 60, null: false
    t.bigint "fixed_staff_id"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_services_on_name", unique: true
  end

  create_table "staff_machine_relations", force: :cascade do |t|
    t.integer "staff_id"
    t.string "machine"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id"], name: "index_staff_machine_relations_on_staff_id"
  end

  create_table "staff_schedules", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.date "date", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_staff_schedules_on_date"
    t.index ["staff_id", "date", "start_time"], name: "index_staff_schedules_on_staff_id_and_date_and_start_time", unique: true
  end

  create_table "staff_services", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.string "service", limit: 20, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id", "service"], name: "index_staff_services_on_staff_id_and_service", unique: true
  end

  create_table "staffs", force: :cascade do |t|
    t.integer "user_id"
    t.string "name"
    t.boolean "active_flag", default: false, null: false
    t.string "name_kanji"
    t.boolean "dismiss_flag", default: false, null: false
    t.boolean "new_customer_flag", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "capacity", default: 1, null: false
    t.integer "nomination_fee", default: 0, null: false
    t.string "assignment_type", limit: 20, default: "nominatable", null: false
  end

  create_table "user_backups", force: :cascade do |t|
    t.string "email"
    t.string "encrypted_password"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "name_kana"
    t.string "name"
    t.string "tel"
    t.date "birthday"
    t.string "introducer"
    t.string "gender"
    t.text "remarks"
    t.string "membership_number"
    t.string "user_type"
    t.string "abo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_types", force: :cascade do |t|
    t.string "type_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "name_kana"
    t.string "name"
    t.string "tel"
    t.date "birthday"
    t.string "introducer"
    t.string "gender"
    t.text "remarks"
    t.string "membership_number"
    t.string "user_type", default: "0"
    t.string "abo", default: "other", null: false
    t.boolean "registration_status", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "body_marks", "medical_questionnaires"
  add_foreign_key "consents", "consent_documents"
  add_foreign_key "consents", "intake_sessions"
  add_foreign_key "consents", "users"
  add_foreign_key "handwriting_entries", "medical_questionnaires"
  add_foreign_key "intake_sessions", "users"
  add_foreign_key "intake_sessions", "users", column: "issuer_id"
  add_foreign_key "karte_access_logs", "users", column: "actor_id"
  add_foreign_key "karte_access_logs", "users", column: "patient_id"
  add_foreign_key "medical_questionnaires", "intake_sessions"
  add_foreign_key "medical_questionnaires", "users"
  add_foreign_key "medical_questionnaires", "users", column: "reviewed_by_id"
  add_foreign_key "ms_inquiry_answers", "metatron_sale_inquiries"
  add_foreign_key "patient_profiles", "users"
  add_foreign_key "reservations", "staffs"
  add_foreign_key "reservations", "users"
  add_foreign_key "schedules", "staffs"
  add_foreign_key "schedules", "users"
  add_foreign_key "services", "staffs", column: "fixed_staff_id"
  add_foreign_key "staff_machine_relations", "staffs"
  add_foreign_key "staff_schedules", "staffs"
  add_foreign_key "staff_services", "staffs"
end
