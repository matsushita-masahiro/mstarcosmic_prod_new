class IntakeSession < ApplicationRecord
  EXPIRY = 30.minutes

  belongs_to :user
  belongs_to :issuer, class_name: "User"

  has_one :medical_questionnaire, dependent: :nullify
  has_one :consent, dependent: :nullify

  # 訂正のときだけ、どの版を直すのかを持つ。
  belongs_to :target_questionnaire, class_name: "MedicalQuestionnaire", optional: true

  # 入口（Intake::SessionsController）の行き先がこれで変わる。
  enum :purpose, { initial: 0, revision: 1 }, prefix: true

  attr_reader :raw_token

  scope :active, -> { where(completed_at: nil, revoked_at: nil).where(expires_at: Time.current..) }

  def self.issue!(patient:, issuer:, issuer_ip: nil,
                  purpose: :initial, target_questionnaire: nil)
    active.where(user: patient).update_all(revoked_at: Time.current)

    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: patient, issuer: issuer, issuer_ip: issuer_ip,
      purpose: purpose, target_questionnaire: target_questionnaire,
      token_digest: digest(raw), expires_at: EXPIRY.from_now
    )
    record.instance_variable_set(:@raw_token, raw)
    record
  end

  # 訂正用の入場トークン。
  #
  # 対象は「指定された版」ではなく「その系列の末端（確定版）」にする。
  # v2 を2回続けて直すとき、2回目も v2 を対象にすると v2 に訂正版が
  # 2つ並列にぶら下がり、どちらが有効か決まらなくなる。
  # 末端を対象にすることで v2 → v2' → v2'' と鎖になる。
  #
  # 末端は確定版だけで辿る。記入途中の v2'（下書き）がある状態で
  # 発行し直したときは対象が v2 のままになり、その下書きの続きから
  # 書ける。ここで v2' を対象にすると、提出していない版に対する
  # 訂正版（v2''）を作ってしまう。
  def self.issue_revision!(patient:, issuer:, target:, issuer_ip: nil)
    issue!(patient: patient, issuer: issuer, issuer_ip: issuer_ip,
           purpose: :revision, target_questionnaire: target.finalized_revision_tip)
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
