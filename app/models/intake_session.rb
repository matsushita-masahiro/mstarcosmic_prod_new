class IntakeSession < ApplicationRecord
  EXPIRY = 30.minutes

  belongs_to :user
  belongs_to :issuer, class_name: "User"
  has_one :medical_questionnaire, dependent: :nullify
  has_one :consent, dependent: :nullify

  attr_reader :raw_token

  scope :active, -> { where(completed_at: nil, revoked_at: nil).where(expires_at: Time.current..) }

  def self.issue!(patient:, issuer:, issuer_ip: nil)
    active.where(user: patient).update_all(revoked_at: Time.current)

    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: patient, issuer: issuer, issuer_ip: issuer_ip,
      token_digest: digest(raw), expires_at: EXPIRY.from_now
    )
    record.instance_variable_set(:@raw_token, raw)
    record
  end

  def self.authenticate(raw)
    return nil if raw.blank?
    record = find_by(token_digest: digest(raw))
    record&.active? ? record : nil
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def active?
    completed_at.nil? && revoked_at.nil? && expires_at.future?
  end

  def complete!(ip: nil, user_agent: nil)
    update!(completed_at: Time.current, client_ip: ip, client_user_agent: user_agent)
  end

  def revoke! = update!(revoked_at: Time.current)
end
