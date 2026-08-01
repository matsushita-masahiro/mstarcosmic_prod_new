class PatientProfile < ApplicationRecord
  belongs_to :user

  enum :sex, { male: 0, female: 1, other: 2 }, prefix: true
  enum :blood_type, { a: 0, b: 1, o: 2, ab: 3, unknown: 4 }, prefix: true
  enum :referral_source, { introduction: 0, hp: 1, other: 2 }, prefix: true

  validates :postal_code, format: { with: /\A\d{7}\z/, allow_blank: true }

  before_validation :normalize_postal_code

  def member_no = format("%06d", user_id)

  def full_address
    [prefecture, city, address_line, building].compact_blank.join(" ")
  end

  def age(on: Date.current)
    return nil if birth_date.blank?
    years = on.year - birth_date.year
    years -= 1 if ([on.month, on.day] <=> [birth_date.month, birth_date.day]) == -1
    years
  end

  private

  def normalize_postal_code
    self.postal_code = postal_code&.gsub(/[^0-9]/, "")&.presence
  end
end
