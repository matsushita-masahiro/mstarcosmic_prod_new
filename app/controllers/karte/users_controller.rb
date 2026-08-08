module Karte
  class UsersController < BaseController
    # カルテ対象外の user_type（1=管理者 / 10=施術スタッフ）
    # 定義は UserKarte 側に置く。施術メモの担当者候補でも同じ区分を使うため。
    NON_PATIENT_TYPES = UserKarte::STAFF_USER_TYPES
    PER_PAGE = 50

    # 電話番号検索で正規化を使う最小桁数。
    # これ未満は候補が絞れないため通常の部分一致に任せる
    # （「090」で700件以上出ても意味がない）。
    MIN_TEL_DIGITS = 5

    def index
      @q = params[:q].to_s.strip
      @page = [params[:page].to_i, 1].max

      scope = User.where("users.user_type IS NULL OR users.user_type NOT IN (?)",
                         NON_PATIENT_TYPES)

      scope = apply_search(scope) if @q.present?

      @total = scope.count
      @total_pages = (@total / PER_PAGE.to_f).ceil

      @users = scope.includes(:patient_profile, :medical_questionnaires)
                    .order(id: :desc)
                    .offset((@page - 1) * PER_PAGE)
                    .limit(PER_PAGE)

      @signed_user_ids = signed_user_ids(@users)
    end

    def show
      @user = User.find(params[:id])
      @profile = @user.patient_profile
      # 手書き画像と人体図マーカーを先に読む。
      # 設問18問ぶんを1件ずつ引くと表示のたびに数十クエリになる。
      @questionnaires = @user.medical_questionnaires
                             .includes(:body_marks,
                                       handwriting_entries: { image_attachment: :blob })
                             .latest_first.limit(10)
      @latest_questionnaire = @questionnaires.first
      @questionnaire = selected_questionnaire
      @consents = @user.consents.includes(:consent_document).latest_first

      @first_visit_at = @user.first_visit_at
      @active_intake = @user.intake_sessions.active.first

      log_access!(patient: @user, action: "show")
    end

    private

    # 2回目以降の来店ぶんを切り替えて見る。
    # 読み込み済みの配列から選ぶので追加クエリは出ない。
    # 他人の問診票 ID を渡されても @questionnaires の中にしか無いため拾えない。
    def selected_questionnaire
      requested = params[:questionnaire_id].presence
      (requested && @questionnaires.find { |q| q.id == requested.to_i }) || @questionnaires.first
    end

    def apply_search(scope)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      digits = normalized_tel_query

      return scope.where(
        "users.name ILIKE :q OR users.name_kana ILIKE :q OR users.tel ILIKE :q " \
        "OR CAST(users.id AS TEXT) = :exact",
        q: like, exact: @q
      ) if digits.blank?

      # 電話番号は表記が揃っていない（詰め731件 / 半角スペース区切り63件 /
      # ハイフン43件 / +81 付き13件）。入力文字列をそのまま照合すると
      # 表記が違うだけで引けないため、両側から数字以外を除いて比較する。
      # 保存側の "+81…" は先頭 81 を 0 に読み替えて国内表記と突き合わせる。
      # 国内番号は必ず 0 始まりのため、81 始まりになるのは +81 の場合だけ。
      scope.where(
        "users.name ILIKE :q OR users.name_kana ILIKE :q " \
        "OR regexp_replace(regexp_replace(users.tel, '[^0-9]', '', 'g'), '^81', '0') LIKE :tel " \
        "OR CAST(users.id AS TEXT) = :exact",
        q: like, tel: "%#{digits}%", exact: @q
      )
    end

    def normalized_tel_query
      digits = @q.gsub(/\D/, "")
      return nil if digits.length < MIN_TEL_DIGITS

      @q.start_with?("+81") ? digits.sub(/\A81/, "0") : digits
    end

    # 一覧の同意書欄。1行ずつ Consent.current_for? を呼ぶと
    # 50行で100クエリになるため、表示分をまとめて引く。
    def signed_user_ids(users)
      document = ConsentDocument.current
      return Set.new if document.nil? || users.empty?

      Consent.where(consent_document: document, user_id: users.map(&:id))
             .distinct.pluck(:user_id).to_set
    end
  end
end
