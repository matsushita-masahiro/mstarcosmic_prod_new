class ConsentDocument < ApplicationRecord
  has_many :consents, dependent: :restrict_with_error

  validates :version, :title, :body, presence: true
  validates :version, uniqueness: true

  before_validation :compute_digest

  scope :published, -> { where.not(published_at: nil).where(archived_at: nil) }

  def self.current = published.order(published_at: :desc).first

  def intact? = body_digest == Digest::SHA256.hexdigest(body)

  private

  def compute_digest
    self.body_digest = Digest::SHA256.hexdigest(body.to_s)
  end
end
