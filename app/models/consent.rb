class Consent < ApplicationRecord
  belongs_to :user
  belongs_to :consent_document
  belongs_to :intake_session, optional: true

  has_one_attached :signature_image

  enum :signer_relation, { self_signed: 0, guardian: 1, other: 2 }, prefix: :signer

  validates :agreed_at, presence: true
  # 署名画像は保存後に添付するため、ここでは strokes の有無のみ検証する
  validate :signature_present

  scope :latest_first, -> { order(agreed_at: :desc) }

  def self.current_for?(user)
    doc = ConsentDocument.current
    doc.present? && exists?(user: user, consent_document: doc)
  end

  private

  def signature_present
    return if signature_strokes.present? || signature_image.attached?
    errors.add(:base, "署名が入力されていません")
  end
end
