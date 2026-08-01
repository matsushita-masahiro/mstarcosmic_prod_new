class BodyMark < ApplicationRecord
  belongs_to :medical_questionnaire

  enum :side, { front: 0, back: 1 }, prefix: true
  enum :mark_type, { pain: 0, numbness: 1, stiffness: 2, other: 3 }, prefix: true

  validates :x, :y, numericality: { in: 0.0..1.0 }
  validates :severity, numericality: { in: 1..5 }, allow_nil: true

  def near?(mark, radius: 0.05)
    side == mark.side &&
      Math.sqrt((x - mark.x)**2 + (y - mark.y)**2) <= radius
  end
end
