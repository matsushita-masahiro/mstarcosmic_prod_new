module Karte
  class UsersController < BaseController
    # カルテ対象外の user_type（1=管理者 / 10=施術スタッフ）
    NON_PATIENT_TYPES = %w[1 10].freeze
    PER_PAGE = 50

    def index
      @q = params[:q].to_s.strip
      @page = [params[:page].to_i, 1].max

      scope = User.where("users.user_type IS NULL OR users.user_type NOT IN (?)",
                         NON_PATIENT_TYPES)

      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where(
          "users.name ILIKE :q OR users.name_kana ILIKE :q OR users.tel ILIKE :q " \
          "OR CAST(users.id AS TEXT) = :exact",
          q: like, exact: @q
        )
      end

      @total = scope.count
      @total_pages = (@total / PER_PAGE.to_f).ceil

      @users = scope.includes(:patient_profile, :medical_questionnaires)
                    .order(id: :desc)
                    .offset((@page - 1) * PER_PAGE)
                    .limit(PER_PAGE)
    end

    def show
      @user = User.find(params[:id])
      @profile = @user.patient_profile
      @questionnaires = @user.medical_questionnaires.latest_first.limit(10)
      @latest_questionnaire = @questionnaires.first
      @consents = @user.consents.includes(:consent_document).latest_first
      @first_visit_at = @user.first_visit_at
      @active_intake = @user.intake_sessions.active.first

      log_access!(patient: @user, action: "show")
    end
  end
end
