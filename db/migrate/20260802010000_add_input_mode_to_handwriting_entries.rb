# handwriting_entries に入力方式を記録する。
# ペンとキーボードを切り替え可能にしたため、どちらで入力されたかを保持する。
class AddInputModeToHandwritingEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :handwriting_entries, :input_mode, :integer, null: false, default: 0
    # 0: pen（strokes + image を保持）
    # 1: keyboard（transcribed_text に直接入力された内容が入る）
  end
end
