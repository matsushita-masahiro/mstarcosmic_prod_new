class CreateMsInquiryAnswers < ActiveRecord::Migration[8.0]
  def change
    create_table :ms_inquiry_answers do |t|
      t.references :metatron_sale_inquiry, foreign_key: true
      t.text :comment      
      t.timestamps
    end
  end
end
