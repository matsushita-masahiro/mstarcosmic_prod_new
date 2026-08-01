class HandwritingEntry < ApplicationRecord
  belongs_to :medical_questionnaire

  has_one_attached :image

  encrypts :transcribed_text

  validates :question_key, presence: true,
            uniqueness: { scope: :medical_questionnaire_id }

  def blank_entry? = strokes.blank? && !image.attached?
end
