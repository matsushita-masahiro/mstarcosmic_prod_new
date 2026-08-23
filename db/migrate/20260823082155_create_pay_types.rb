class CreatePayTypes < ActiveRecord::Migration[8.0]
  def up
    return if table_exists?(:pay_types)

    create_table :pay_types, id: :integer do |t|
      t.string  :pay_name
      t.integer :price
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.integer :user_type_id
      t.text    :paypal_form
    end
  end

  def down
    drop_table :pay_types, if_exists: true
  end
end