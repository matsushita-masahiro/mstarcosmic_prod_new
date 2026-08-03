class MedicalQuestionnaire < ApplicationRecord
  include MedicalQuestionnaireFlags

  belongs_to :user
  belongs_to :intake_session, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :handwriting_entries, dependent: :destroy
  has_many :body_marks, dependent: :destroy

  accepts_nested_attributes_for :handwriting_entries, :body_marks, allow_destroy: true

  enum :status, { draft: 0, submitted: 1, reviewed: 2 }, prefix: true

  validates :form_version, presence: true
  validates :pregnancy_weeks, numericality: { in: 1..45 }, allow_nil: true

  before_save :promote_flags_from_answers

  scope :latest_first, -> { order(Arel.sql("COALESCE(submitted_at, created_at) DESC")) }

  def submit!(intake_session: nil)
    update!(status: :submitted, submitted_at: Time.current, intake_session: intake_session)
  end

  def answer(key) = answers[key.to_s]
end
