class Consent < ApplicationRecord
  belongs_to :user
  belongs_to :consent_document
  belongs_to :intake_session, optional: true

  has_one_attached :signature_image

  enum :signer_relation, { self_signed: 0, guardian: 1, other: 2 }, prefix: :signer

  validates :agreed_at, presence: true
  # 署名画像は保存後に添付するため、ここでは strokes の有無のみ検証する
  validate :signature_present
  # 入口とコントローラで弾いているが、同時送信までは防げないので最後の砦を置く
  validate :not_signed_twice, on: :create

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

  # 同じ患者が同じ版に2件目を作ることを防ぐ。
  #
  # 改訂して再署名を求める場合は consent_document_id が変わるので、
  # この制約に引っかからない。同じ版に意図的に2回署名する運用は無い。
  #
  # on: :create に限っているのは、本番に既にある重複（2名・4件）を
  # 更新できなくしないため。署名画像は保存後に attach するので、
  # そこで走る save がこの検証で落ちると画像だけ付かない事故になる。
  #
  # DB の unique 制約は入れていない。既存の重複があるとマイグレーションが
  # 通らないため。重複を消してから改めて検討すること。
  def not_signed_twice
    return if user_id.blank? || consent_document_id.blank?
    return unless Consent.exists?(user_id: user_id, consent_document_id: consent_document_id)

    errors.add(:base, "この同意書には既に署名済みです")
  end
end
