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

    # 並べ替えを許可する列。params[:sort] をそのまま order() に渡すと
    # SQL インジェクションになるため、ここに無い値は既定へ落とす。
    # 実際の SQL 断片は sort_expression で組み立てる。
    SORT_KEYS = %w[member_no name birthday gender consent questionnaire].freeze
    DIRECTIONS = %w[asc desc].freeze

    # ヘッダーを初めて押したときの向き。
    # 生年月日は「若い順」、同意書は「署名済が先」、問診票は「件数の多い順」を
    # 最初に見たいので降順から始める。
    FIRST_DIRECTION = {
      "member_no"     => "asc",
      "name"          => "asc",
      "birthday"      => "desc",
      "gender"        => "asc",
      "consent"       => "desc",
      "questionnaire" => "desc"
    }.freeze

    # 並べ替えを指定していないときの既定。従来の表示のまま。
    DEFAULT_SORT = "member_no"
    DEFAULT_DIRECTION = "desc"

    def index
      @q = params[:q].to_s.strip
      @page = [params[:page].to_i, 1].max
      @sort, @direction = sort_params

      scope = User.where("users.user_type IS NULL OR users.user_type NOT IN (?)",
                         NON_PATIENT_TYPES)

      scope = apply_search(scope) if @q.present?

      @total = scope.count
      @total_pages = (@total / PER_PAGE.to_f).ceil

      @users = scope.includes(:patient_profile, :medical_questionnaires)
                    .order(Arel.sql(order_clause))
                    .offset((@page - 1) * PER_PAGE)
                    .limit(PER_PAGE)

      @signed_user_ids = signed_user_ids(@users)
    end

    def show
      @user = User.find(params[:id])
      @profile = @user.patient_profile
      # 手書き画像と人体図マーカーを先に読む。
      # 設問18問ぶんを1件ずつ引くと表示のたびに数十クエリになる。
      # previous_version は履歴表の各行が「◯◯の訂正」を出すのに使う。
      # 10行ぶん1件ずつ引くとそのまま N+1 になる。
      @questionnaires = @user.medical_questionnaires
                             .includes(:body_marks, :previous_version,
                                       signature_image_attachment: :blob,
                                       handwriting_entries: { image_attachment: :blob })
                             .latest_first.limit(10)
      # 「修正」ボタンを出す版を決めるために、系列を辿れる全件を持っておく。
      # 履歴表は最新10件しか出さないが、末端の判定をその窓の中だけで行うと、
      # 窓の外に訂正版がある版を末端と誤判定してボタンが増える。
      # finalized_revision_tip に渡すとクエリを出さずに辿れる。
      @all_questionnaires = @user.medical_questionnaires.to_a

      # 警告の根拠は確定版のみから取る。@questionnaires は履歴表用で下書きも含むため、
      # ここから先頭を取ると書きかけの下書きが確定版を押しのけ、
      # 確定版の禁忌が画面から消える。
      @latest_questionnaire = @user.latest_questionnaire
      @questionnaire = selected_questionnaire

      # 手書きの新旧を色分けするための境界。表示中の版が決まってから組み立てる。
      # カルテ側でだけ渡す。患者の確認画面は同じ partial を描くが、
      # これを渡さないので単色になる。渡さなければ色分けのしようがない、
      # という形で安全側に倒している。
      @stroke_boundaries = @questionnaire&.inherited_stroke_counts || {}

      # 表示中の版が訂正版なら、前版との差分を出す。
      # 訂正版でなければ present? が false になり、画面には何も出ない。
      @revision_diff = QuestionnaireRevisionDiff.new(@questionnaire)

      # 警告バナーは「いまの患者の状態」を表すので、表示中の版ではなく
      # 施術判断の根拠になる版（@latest_questionnaire）で見る。
      @latest_revision_diff = QuestionnaireRevisionDiff.new(@latest_questionnaire)

      # スタッフの追記。表示中の版だけでなく、版の連なり全体から集める。
      # v1 に書いた申し送りが、患者が v2 を出した瞬間に最新版の画面から
      # 黙って消えるのを避けるため。過去版を開けば見えるとしても気づかれない。
      # レコード自体は書かれた版にぶら下げたまま動かさない（追加専用のため）。
      @annotations = annotations_for(@questionnaire)

      @consents = @user.consents.includes(:consent_document).latest_first

      @first_visit_at = @user.first_visit_at
      @active_intake = @user.intake_sessions.active.first

      log_access!(patient: @user, action: "show")
    end

    private

    # 許可した値だけを通す。外れた値（未指定・存在しない列・"id; DROP …"）は
    # 既定へ落とすので、order() には常にここで作った SQL しか渡らない。
    # 列だけ指定して向きを省いた URL では、その列の初回の向きを使う。
    def sort_params
      key = SORT_KEYS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT

      direction =
        if DIRECTIONS.include?(params[:direction])
          params[:direction]
        elsif SORT_KEYS.include?(params[:sort])
          FIRST_DIRECTION.fetch(key)
        else
          DEFAULT_DIRECTION
        end

      [key, direction]
    end

    # 第2キーに id を必ず付ける。性別や同意書のように同じ値が数百行続く列では、
    # これが無いと Postgres が同順位の行を返す順を保証せず、
    # offset/limit のページ送りで同じ人が2回出たり消えたりする。
    def order_clause
      "#{sort_expression} #{@direction} NULLS LAST, users.id #{@direction}"
    end

    # 値が無い行（カナ空欄 / 生年月日なし / 性別未登録 / 未署名 / 問診票0件）は
    # NULL に寄せる。order_clause が NULLS LAST を付けるため、
    # 昇順・降順のどちらでも「—」の行が常に最後にまとまる。
    def sort_expression
      case @sort
      when "name"          then "NULLIF(users.name_kana, '')"
      when "birthday"      then "users.birthday"
      when "gender"        then gender_rank_sql
      when "consent"       then consent_signed_sql
      when "questionnaire" then questionnaire_count_sql
      else "users.id" # member_no は id のゼロ埋め表示なので id で並ぶ
      end
    end

    # gender は表記ゆれがあるため（f / m / nil / 男性）、
    # 生の値ではなく gender_label と同じ判定で 女性→男性 の順位に直して並べる。
    # 判定に使う値は UserKarte と共有し、片方だけ増えることがないようにする。
    # どちらにも該当しない「未登録」は NULL のままにして最後へ送る。
    def gender_rank_sql
      ActiveRecord::Base.sanitize_sql_array(
        ["CASE WHEN LOWER(users.gender) IN (?) THEN 0 " \
         "WHEN LOWER(users.gender) IN (?) THEN 1 END",
         UserKarte::FEMALE_VALUES, UserKarte::MALE_VALUES]
      )
    end

    # 一覧の「署名済」と同じ条件。行ごとに引くのではなく相関サブクエリにして
    # 一覧本体の1クエリで並べ替える（consents の (user_id, consent_document_id)
    # インデックスが効く）。未署名は FALSE ではなく NULL にして最後へ送る。
    # 現行の同意書が無いときは全員が未署名なので、並べ替えるものが無い。
    def consent_signed_sql
      document = current_consent_document
      return "NULL" if document.nil?

      ActiveRecord::Base.sanitize_sql_array(
        ["NULLIF(EXISTS (SELECT 1 FROM consents WHERE consents.user_id = users.id " \
         "AND consents.consent_document_id = ?), FALSE)", document.id]
      )
    end

    # 一覧に出している件数と同じ（status を問わない全件）。
    # 0件は「—」表示なので NULL に寄せて最後へ送る。
    def questionnaire_count_sql
      "NULLIF((SELECT COUNT(*) FROM medical_questionnaires " \
      "WHERE medical_questionnaires.user_id = users.id), 0)"
    end

    def current_consent_document
      return @current_consent_document if defined?(@current_consent_document)

      @current_consent_document = ConsentDocument.current
    end

    # 2回目以降の来店ぶんを切り替えて見る。
    # 読み込み済みの配列から選ぶので追加クエリは出ない。
    # 他人の問診票 ID を渡されても @questionnaires の中にしか無いため拾えない。
    # question_key => [QuestionnaireAnnotation] （古い順）。
    # 版を辿るのは MedicalQuestionnaire#revision_chain を流用している
    # （循環参照でも止まる作りになっている）。
    def annotations_for(questionnaire)
      return {} if questionnaire.nil?

      QuestionnaireAnnotation
        .where(medical_questionnaire_id: questionnaire.revision_chain.map(&:id))
        .includes(:staff, :medical_questionnaire)
        .chronological
        .group_by(&:question_key)
    end

    def selected_questionnaire
      requested = params[:questionnaire_id].presence
      (requested && @questionnaires.find { |q| q.id == requested.to_i }) || default_questionnaire
    end

    # 既定は確定版。警告バナーと同じ版を見せる。
    # 下書きを既定にすると、バナーが確定版の禁忌を出している真下に
    # その項目が空の下書きが並び、バナーの方が疑われる。
    # 下書きは履歴表から明示的に選べば見られる。
    #
    # @latest_questionnaire をそのまま返さないのは、あれが別クエリで読んだ
    # 素の1件で show の includes が効いておらず、パネルに描くと手書き欄・
    # マーカーぶんのクエリが出るため。同じ ID を preload 済みの
    # @questionnaires から引き直す。
    #
    # 引き直せないのは、確定版より新しい下書きが10件を超えて並んだときだけ。
    # そのときは preload 無しでもバナーと同じ版を出す方を採る（表示の一致を優先）。
    #
    # 確定版が1件も無ければ下書きを見せる。何も表示しないより、
    # 書きかけでも内容が見える方が有用なため。
    # このとき警告バナーは出ない（@latest_questionnaire が nil のまま）。
    def default_questionnaire
      return @questionnaires.first if @latest_questionnaire.nil?

      @questionnaires.find { |q| q.id == @latest_questionnaire.id } || @latest_questionnaire
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
      document = current_consent_document
      return Set.new if document.nil? || users.empty?

      Consent.where(consent_document: document, user_id: users.map(&:id))
             .distinct.pluck(:user_id).to_set
    end
  end
end
