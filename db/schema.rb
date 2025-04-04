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

ActiveRecord::Schema[8.0].define(version: 2025_04_04_175508) do
  create_table "answers", force: :cascade do |t|
    t.integer "inquiry_id"
    t.integer "user_id"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "coupons", force: :cascade do |t|
    t.integer "payment_id"
    t.string "status"
    t.integer "order_number"
    t.string "remarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "inquiries", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "machine_schedules", force: :cascade do |t|
    t.date "machine_schedule_date"
    t.float "machine_schedule_space"
    t.string "machine"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "machines", force: :cascade do |t|
    t.string "name"
    t.integer "number_of_machine"
    t.string "short_word"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "page_contents", force: :cascade do |t|
    t.text "content"
    t.integer "user_type_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "staff_machine_relations", force: :cascade do |t|
    t.integer "staff_id"
    t.string "machine"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id"], name: "index_staff_machine_relations_on_staff_id"
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

  add_foreign_key "schedules", "staffs"
  add_foreign_key "schedules", "users"
  add_foreign_key "staff_machine_relations", "staffs"
end
