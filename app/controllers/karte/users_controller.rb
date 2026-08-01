module Karte
  class UsersController < BaseController
    # カルテ対象外の user_type（1=管理者 / 10=施術スタッフ）
    NON_PATIENT_TYPES = %w[1 10].freeze

    def index
      @q = params[:q].to_s.strip
      scope = User.where("users.user_type IS NULL OR users.user_type NOT IN (?)",
                         NON_PATIENT_TYPES)
                  .left_joins(:patient_profile)

      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where(
          "users.name ILIKE :q OR patient_profiles.name_kana ILIKE :q " \
          "OR patient_profiles.name_roman ILIKE :q OR CAST(users.id AS TEXT) = :exact",
          q: like, exact: @q
        )
      end

      @users = scope.includes(:patient_profile).order(id: :desc).limit(300)
    end

    def show
      @user = User.find(params[:id])
      @profile = @user.patient_profile || @user.build_patient_profile
      @questionnaires = @user.medical_questionnaires.latest_first.limit(10)
      @latest_questionnaire = @questionnaires.first
      @consents = @user.consents.includes(:consent_document).latest_first
      @first_visit_at = first_visit_at(@user)
      @active_intake = @user.intake_sessions.active.first

      log_access!(patient: @user, action: "show")
    end

    private

    # 初診日 = 最初の同意署名日。無ければ最初の問診票提出日。
    def first_visit_at(user)
      user.consents.minimum(:agreed_at) ||
        user.medical_questionnaires.minimum(:submitted_at)
    end
  end
end
