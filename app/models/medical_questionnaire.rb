class MedicalQuestionnaire < ApplicationRecord
  include MedicalQuestionnaireFlags

  belongs_to :user
  belongs_to :intake_session, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :handwriting_entries, dependent: :destroy
  has_many :body_marks, dependent: :destroy

  # 訂正（版管理）。提出済みの問診票を直すときは上書きせず、次の版を作る。
  #
  #   v2 ─ previous_version ─→ nil        （独立した提出。revision 1）
  #   v2' ─ previous_version ─→ v2        （v2 を訂正した版。revision 2）
  #   v2 ─ revised_version ──→ v2'
  #
  # dependent: :nullify は患者削除のため。User の dependent: :destroy が
  # 問診票を1件ずつ消すとき、前版が先に消えると外部キーで落ちる。
  belongs_to :previous_version, class_name: "MedicalQuestionnaire",
             foreign_key: :previous_id, optional: true, inverse_of: :revised_version
  has_one :revised_version, class_name: "MedicalQuestionnaire",
          foreign_key: :previous_id, dependent: :nullify, inverse_of: :previous_version

  accepts_nested_attributes_for :handwriting_entries, :body_marks, allow_destroy: true

  # 確認署名。同意書（Consent）と同じ持ち方にしている。
  has_one_attached :signature_image

  enum :status, { draft: 0, submitted: 1, reviewed: 2 }, prefix: true

  # 値は Consent と同じにする。同じ来店の同意書署名と問診票署名を突き合わせて
  # 「別人だ」と誤判定しないために記録しているので、対応表を挟まずに
  # 比べられる形でないと意味がない。
  #
  # 画面で選ばせるのは本人（self_signed）と代理人（guardian）の2つだけ。
  # other は Consent に合わせて残してあるが、患者に3択を出しても
  # 「代理人」と「その他」の区別がつかないため出していない。
  enum :signer_relation, { self_signed: 0, guardian: 1, other: 2 }, prefix: :signer

  validates :form_version, presence: true
  validates :pregnancy_weeks, numericality: { in: 1..45 }, allow_nil: true
  validates :revision, numericality: { greater_than_or_equal_to: 1 }

  # 1つの版に訂正版は1つだけ。v2 を2回直したら v2 → v2' → v2'' と鎖にする。
  # v2 に v2' と v2'' が並列にぶら下がると、どちらが有効か決まらなくなる。
  #
  # 発行側（IntakeSession.issue_revision!）が系列の末端を対象にするので
  # 通常は並列にならないが、判断を呼ぶ側の注意力に預けない。
  validate :revision_does_not_branch

  # 署名の検証は「下書きから確定へ移るとき」だけに効かせる。
  #
  # 無条件にすると3か所で落ちる。
  #   1. 記入中の autosave（Intake::QuestionnairesController#update）。
  #      署名前なので当然 nil で、30秒ごとに保存が失敗する
  #   2. 署名の運用開始前に提出された既存レコード（本番11件・staging 12件）。
  #      reviewed への更新も、KarteAttachment.attach! が走らせる record.save も
  #      すべて落ちるようになる
  #   3. KarteAttachment.attach!（署名画像の添付）。永続化済みレコードに
  #      record.save を走らせるため、Consent で一度踏んでいる罠
  #
  # on: :create にはできない。案A（下書きを保存してから署名で確定）では
  # 署名は update で入るので、create の時点では必ず空になる。
  validate :signature_present, if: :finalizing?
  validate :signer_name_present, if: :finalizing?

  before_validation :inherit_revision_number

  before_save :promote_flags_from_answers

  # 第2キーに id を必ず付ける。提出が同時刻の2件（訂正の再提出や、
  # まとめて取り込んだ紙カルテ）では COALESCE の値が並び、
  # これが無いと Postgres が返す順を保証しない。
  # カルテ一覧の「施術不可 / 要確認」バッジと、カルテ詳細の警告バナー・
  # 内容パネルの既定は、どれも finalized の先頭1件を見る。
  # 順序が揺れると古い版の判定が画面に出る。
  # Ruby 側で選ぶ UserKarte#latest_finalized_questionnaire も同じ並びにすること。
  scope :latest_first, -> { order(Arel.sql("COALESCE(submitted_at, created_at) DESC, id DESC")) }

  # 患者が提出を完了し、確定した状態。draft 以外。
  #
  # submitted / reviewed を列挙するのではなく draft を除く形にしているのは、
  # 将来 status に値が増えたときに自動で含まれるようにするため。
  # 列挙にすると、追加した値が最新版の判定から静かに漏れる。
  #
  # confirmed ではなく finalized なのは、同じカルテ機能の中に
  # needs_confirmation? / confirmation_reasons（禁忌ではないが要確認）という
  # 無関係な概念があり、並ぶと互いの前提だと誤読されるため。
  # Reservation.confirmed（予約確定）とも別物。
  scope :finalized, -> { where.not(status: :draft) }

  # ── 版の系列 ────────────────────────────────
  #
  # 循環参照（データ不整合）でも止まるよう、辿った id を控えながら進む。
  # 参照が壊れた状態でカルテを開くと無限ループでプロセスが固まるため、
  # 「正しいデータなら起きない」では済ませない。

  # 系列の起点。独立した提出まで遡る。
  def revision_origin
    walk(:previous_version)
  end

  # 系列の末端。最も新しい訂正版。下書きの訂正版も含む。
  def revision_tip
    walk(:revised_version)
  end

  # 起点から末端までの全版。履歴や差分表示で使う。
  def revision_chain
    chain = [ revision_origin ]
    seen = Set.new([ chain.first.id ])

    while (nxt = chain.last.revised_version)
      break unless seen.add?(nxt.id)
      chain << nxt
    end

    chain
  end

  # 確定版だけを辿った末端。施術判断はこれを見る。
  #
  # 記入中の訂正版（下書き）で止まるのが要点。下書きを末端にすると、
  # 患者が訂正を書き始めた瞬間に、確定していない内容で施術可否が決まる。
  #
  # within に読み込み済みの問診票を渡すと、そこから辿ってクエリを出さない。
  # カルテ一覧は includes 済みの関連を持っており、行ごとに辿るとN+1になる。
  def finalized_revision_tip(within: nil)
    children = within&.group_by(&:previous_id)
    current = self
    seen = Set.new([ id ])

    loop do
      nxt = children ? children[current.id]&.min_by(&:id) : current.revised_version
      break if nxt.nil? || nxt.status_draft?
      break unless seen.add?(nxt.id)
      current = nxt
    end

    current
  end

  def submit!(intake_session: nil)
    update!(status: :submitted, submitted_at: Time.current, intake_session: intake_session)
  end

  # 患者が確認画面で署名して確定する。
  #
  # 署名の付与と確定を1回の update! にまとめている。分けると
  # 「署名だけ入って確定していない」「確定したが署名が無い」が作れてしまい、
  # signature_present の検証をすり抜ける経路になる。
  #
  # 確定は必ず submit! を通す。latest_questionnaire（SQL 側）と
  # latest_finalized_questionnaire（Ruby 側）は nil の畳み方が違うため、
  # submit! を経由しない確定の経路ができると両者が食い違う。
  # test/models/user_test.rb が一致を固定している。
  #
  # 下書きでなければ false を返して何もしない。二重送信や、別タブから
  # 確定済みのものをもう一度確定しようとした場合にあたる。
  # 患者にエラーを見せる意味は無いので、呼び出し側は完了画面へ送ればよい。
  # 上書きを許すと、署名を後から差し替える経路になってしまう。
  def sign_and_submit!(intake_session:, signer_name:, signer_relation:,
                       strokes:, ip_address: nil, user_agent: nil)
    return false unless status_draft?

    assign_attributes(
      signed_at: Time.current,
      signer_name: signer_name,
      signer_relation: signer_relation,
      signature_strokes: strokes,
      ip_address: ip_address,
      user_agent: user_agent
    )
    submit!(intake_session: intake_session)
    true
  end

  # 署名がある問診票か。
  # 署名の運用開始前に提出された既存レコードは false になる。
  def signed? = signed_at.present?

  # 問診票で性別を聞いた場合、users 側が未設定なら反映する。
  # 既に値がある場合は上書きしない（患者の自己申告より既存データを優先）。
  #
  # 確定の直前に呼ぶ。以前は Intake::QuestionnairesController#create に
  # 置いていたが、確定が確認画面側へ移ったので、確定と一緒に動くよう
  # answers を持っているこちらへ移した。
  def sync_patient_gender!
    return if user.gender.present?

    value = answer("q0_gender")
    return if value.blank?

    user.update_column(:gender, value == "female" ? "f" : "m")
  end

  def answer(key) = answers[key.to_s]

  # 訂正版か（独立した提出ではないか）
  def revised? = previous_id.present?

  # 記入途中の内容を、患者端末の localStorage と同じ形で返す。
  #
  # intake のフォームはサーバの下書きを ERB では描かず、この JSON を
  # questionnaire_controller.js の復元処理にそのまま渡す。
  # 出所が localStorage でもサーバでも復元は1本のままにするため、
  # 形（キー名・値の型）を端末側に合わせている。
  # saveLocalDraft() の形を変えるときは、ここも一緒に変えること。
  #
  # PNG（image）は含めない。restore() は strokes からしか描き直さず、
  # 表示には要らない。HTML に base64 を埋めると本文が肥大するだけになる。
  #
  # savedAt は端末側と同じくミリ秒。24時間判定には使われない
  # （サーバの下書きは intake_session に紐づき、セッションは30分で失効する）。
  #
  # 戻せるものが何も無いときは nil を返す。空の下書きを渡すと
  # 画面は何も変わらないのに「読み込みました」とだけ出て患者を混乱させる。
  def draft_snapshot
    return nil unless persisted?

    handwriting = handwriting_snapshot
    marks = body_marks_snapshot
    return nil if answers.blank? && handwriting.empty? && marks.empty?

    {
      savedAt: (updated_at.to_f * 1000).round,
      answers: answers,
      handwriting: handwriting,
      bodyMarks: marks
    }
  end

  private

  # いま下書きから確定へ移ろうとしているか。
  #
  # persisted? を条件に入れているのは、新規作成でいきなり submitted を
  # 作る経路（テストのデータ用意や、コンソールからの取り込み）を
  # 巻き込まないため。アプリの導線は必ず下書きを経由するので、
  # 患者の送信がここをすり抜けることはない。
  def finalizing?
    persisted? && !status_draft? && status_changed?(from: "draft")
  end

  def signature_present
    return if signature_strokes.present? || signature_image.attached?

    errors.add(:base, "署名が入力されていません")
  end

  def signer_name_present
    return if signer_name.present?

    errors.add(:base, "署名者のお名前が入力されていません")
  end

  # 同じ前版を指す訂正版が既にいないか。
  # 自分自身は除く（更新のたびに落ちてしまうため）。
  def revision_does_not_branch
    return if previous_id.blank?

    siblings = MedicalQuestionnaire.where(previous_id: previous_id)
    siblings = siblings.where.not(id: id) if persisted?
    return unless siblings.exists?

    errors.add(:base, "この版は既に訂正されています")
  end

  # 訂正版の版番号は前版から数える。呼び出し側に数えさせない。
  def inherit_revision_number
    self.revision = previous_version.revision + 1 if previous_version
  end

  # assoc を辿れなくなるまで進む。循環参照があってもそこで止まる。
  def walk(assoc)
    current = self
    seen = Set.new([ id ])

    while (nxt = current.public_send(assoc))
      break unless seen.add?(nxt.id)
      current = nxt
    end

    current
  end

  # 端末側の collectHandwriting() と同じものだけを返す。
  #
  # collectHandwriting() は空欄のキーを落とすため、こちらが空欄を含めると
  # verifyRestore() が「保存されていたのに画面に戻っていない欄」と数え、
  # restoreVerified が false のまま partial 付きの送信が続いてしまう。
  # 「画面に戻せるか」で揃えるので、中身が空のものはここで落とす。
  def handwriting_snapshot
    handwriting_entries.each_with_object({}) do |entry, result|
      if entry.input_mode_keyboard?
        next if entry.transcribed_text.blank?
        result[entry.question_key] = { mode: "keyboard", text: entry.transcribed_text }
      else
        next if entry.strokes.blank?
        result[entry.question_key] = {
          mode: "pen", strokes: entry.strokes,
          width: entry.canvas_width, height: entry.canvas_height
        }
      end
    end
  end

  # 端末側の body-map は x / y を数値で持つ。
  # decimal のまま to_json すると文字列になり、送り返された値が
  # 端末側と一致しなくなるので float に揃える。
  def body_marks_snapshot
    body_marks.map do |mark|
      { side: mark.side, x: mark.x.to_f, y: mark.y.to_f,
        mark_type: mark.mark_type, note: mark.note }.compact
    end
  end
end
