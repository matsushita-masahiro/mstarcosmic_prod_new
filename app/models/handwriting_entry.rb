class HandwritingEntry < ApplicationRecord
  belongs_to :medical_questionnaire

  has_one_attached :image

  # 要配慮個人情報に該当しうるためカラム単位で暗号化
  encrypts :transcribed_text

  # pen: strokes(JSON) + image(PNG) を保持。将来の手書き認識に備える
  # keyboard: transcribed_text に入力内容が入る
  enum :input_mode, { pen: 0, keyboard: 1 }, prefix: true

  validates :question_key, presence: true,
            uniqueness: { scope: :medical_questionnaire_id }

  def blank_entry?
    if input_mode_keyboard?
      transcribed_text.blank?
    else
      strokes.blank? && !image.attached?
    end
  end

  # スタッフ画面での表示用。キーボード入力ならテキスト、ペンなら nil。
  def display_text
    input_mode_keyboard? ? transcribed_text : nil
  end
end
