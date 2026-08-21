# app/models/concerns/user_karte.rb
#
# User にカルテ関連の振る舞いを追加する。
# 既存の User モデルに include して使う:
#   class User < ApplicationRecord
#     include UserKarte
#     ...
#   end
module UserKarte
  extend ActiveSupport::Concern

  # gender の実データは "f"(667) / "m"(196) / nil(46) / "男性"(1)。
  # 表記ゆれがあるため複数の値を受ける。
  FEMALE_VALUES = %w[f female woman 女 女性].freeze
  MALE_VALUES   = %w[m male man 男 男性].freeze

  # カルテ対象外の user_type（1=管理者 / 10=施術スタッフ）
  # 患者一覧の除外条件と、施術メモの担当者候補の両方で使う。
  STAFF_USER_TYPES = %w[1 10].freeze

  # 会員の削除を拒む理由になる記録。値は画面に出す名前で、並び順もそのまま使う。
  KARTE_RECORDS = {
    medical_questionnaires: "問診票",
    consents: "同意書",
    treatment_notes: "施術メモ"
  }.freeze

  included do
    has_one  :patient_profile, dependent: :destroy
    has_many :medical_questionnaires, dependent: :destroy
    has_many :consents, dependent: :destroy
    has_many :intake_sessions, dependent: :destroy
    has_many :treatment_notes, dependent: :destroy

    # カルテを閲覧された記録。患者を消すときは一緒に消える。
    #
    # actor_id（誰が見たか）側の関連はあえて足していない。足すと
    # スタッフのアカウントを消したときに「誰が見たか」の記録まで消えてしまう。
    # スタッフは物理削除しない運用にする（消そうとすると外部キーで止まる）。
    has_many :karte_access_logs, foreign_key: :patient_id,
             inverse_of: :patient, dependent: :destroy

    # カルテの記録がある会員は削除しない。
    #
    # 削除が想定しているのは「登録を間違えた」「同じ人で2つ作ってしまった」の
    # 掃除だけで、どちらも記録が積み上がる前の操作。記録のある人を消すのは
    # 別の話なので、必要になったらそのときに設計する。
    #
    # これまでは外部キー制約が偶然の防波堤になっていた。
    # karte_access_logs に dependent: :destroy を入れてその壁が無くなるので、
    # 「消してよいか」の判断をここに明示して置く。
    #
    # コントローラではなくモデルに置くのは、コンソールや rake タスクからの
    # 削除も同じ判断を通すため。削除は取り返しがつかないので、
    # 入口の数だけ判定を書く形にしない。
    #
    # prepend: true が要る。has_many の dependent: :destroy が登録する
    # before_destroy より先に走らせないと、子を消してから中止することになる
    # （トランザクションで戻るので実害は無いが、無駄な往復になる）。
    before_destroy :refuse_destroy_with_karte_records, prepend: true

    scope :karte_staff, -> { where(user_type: STAFF_USER_TYPES).order(:id) }
  end

  # 「問診票 2件・同意書 1件」。記録が無ければ nil。
  # 画面の文言もここから作り、数え方を2か所に持たない。
  def karte_records_summary
    KARTE_RECORDS.filter_map { |assoc, label|
      count = public_send(assoc).count
      "#{label} #{count}件" if count.positive?
    }.presence&.join("・")
  end

  # 会員番号（紙運用との突合のためゼロ埋め表示）
  def karte_member_no = format("%06d", id)

  def female? = FEMALE_VALUES.include?(gender.to_s.downcase)
  def male?   = MALE_VALUES.include?(gender.to_s.downcase)

  # 性別が判別できるか。できない場合は問診票の冒頭で聞く。
  def gender_known? = female? || male?

  def gender_label
    return "女性" if female?
    return "男性" if male?
    "未登録"
  end

  def age(on: Date.current)
    return nil if birthday.blank?
    years = on.year - birthday.year
    years -= 1 if ([on.month, on.day] <=> [birthday.month, birthday.day]) == -1
    years
  end

  def birthday_display
    birthday&.strftime("%Y/%m/%d")
  end

  # ── 施術判断の根拠になる「最新の問診票」──────────────
  #
  # 訂正（版管理）が入ったため、単純に「提出時刻が最も新しい1件」では選べない。
  #
  #   v1  v2  v3          … v3 が最新
  #   v2 を訂正 → v2'     … v2' の提出時刻が最も新しいが、直したのは v2 の誤記。
  #                          施術判断は v3 のまま。
  #   v3 を訂正 → v3'     … こちらは最新版の訂正なので v3' に変わる。
  #
  # そこで2段階で選ぶ。
  #   1. 独立した提出（previous_id が nil）のうち、提出が最も新しいもの
  #   2. その版の系列を辿った末端（確定版のみ）
  #
  # 訂正版が1件も無い既存データでは、1段階目が従来と同じ版を選び、
  # 2段階目の末端は自分自身になるので、挙動は変わらない。

  # 下書き以外の最新1件。reviewed（スタッフが確認済みにした版）も含む。
  # status_submitted で絞ると、確認した問診票ほど最新版から漏れる。
  def latest_questionnaire
    medical_questionnaires.finalized.where(previous_id: nil).latest_first.first
                          &.finalized_revision_tip
  end

  # 一覧用。scope を使うと includes 済みでも行ごとにクエリが出るため、
  # 読み込み済みの関連から Ruby 側で絞る。
  #
  # 比較を配列にして id を第2キーにしている。提出が同時刻の2件では
  # submitted_at だけでは決まらず、latest_first（SQL 側）が id DESC で選ぶ版と
  # 食い違って、一覧と詳細で別の問診票が出てしまうため。
  #
  # 系列を辿る段でもクエリを出さない。読み込み済みの一覧をそのまま渡し、
  # 訂正版もその中から探す（一覧は患者の問診票を全件 includes している）。
  def latest_finalized_questionnaire
    all = medical_questionnaires.to_a
    origin = all.reject(&:status_draft?)
                .select { |q| q.previous_id.nil? }
                .max_by { |q| [q.submitted_at || Time.at(0), q.id] }

    origin&.finalized_revision_tip(within: all)
  end

  # 初診日 = 最初の同意署名日。無ければ最初の問診票提出日。
  def first_visit_at
    consents.minimum(:agreed_at) || medical_questionnaires.minimum(:submitted_at)
  end

  private

  def refuse_destroy_with_karte_records
    summary = karte_records_summary
    return if summary.nil?

    errors.add(:base, "この会員には#{summary}の記録があるため削除できません")
    throw :abort
  end
end
