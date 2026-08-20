# test/models/medical_questionnaire_revision_test.rb
#
# 問診票の訂正（版管理）。上書きせず次の版を作る仕組みを守る。
#
# ── なぜ上書きしないか ──────────────────────────
#
# 病歴・服薬・ペースメーカーの有無で施術可否を判断している。
# 上書きすると「当時どう判断したか」の根拠が消える。
# 紙のカルテで修正液を使わず二重線を引くのと同じ考え方。
#
# 差分だけを持って元を書き換える方式は採っていない。記録漏れやバグがあれば
# 元の内容が永久に戻せなくなる。訂正版も完全なレコードとして保存する。
#
# ── ここで守るもの ────────────────────────────
#
# 1. 系列が鎖になること（枝分かれしないこと）
#    v2 に v2' と v2'' が並列にぶら下がると、どちらが有効か決まらない。
#
# 2. 循環参照があっても無限ループしないこと
#    参照が壊れた状態でカルテを開くとプロセスが固まる。
#    「正しいデータなら起きない」では済ませない。
#
# 施術判断がどの版を見るかは test/models/user_test.rb が担当する。
require "test_helper"

class MedicalQuestionnaireRevisionTest < ActiveSupport::TestCase
  setup do
    @patient = create_patient
  end

  test "訂正版は前版から版番号を継ぐ" do
    v1 = create_questionnaire
    v2 = create_revision_of(v1)

    assert_equal 1, v1.revision
    assert_equal 2, v2.revision
    assert_equal 3, create_revision_of(v2).revision
  end

  test "独立した提出は版番号が 1" do
    assert_equal 1, create_questionnaire.revision
  end

  test "前版と訂正版が双方向に辿れる" do
    v1 = create_questionnaire
    v2 = create_revision_of(v1)

    assert_equal v1, v2.previous_version
    assert_equal v2, v1.reload.revised_version
    assert v2.revised?
    assert_not v1.revised?
  end

  # 発行側が末端を対象にするので通常は起きないが、
  # 判断を呼ぶ側の注意力に預けない。
  test "同じ版に2つ目の訂正版は作れない" do
    v1 = create_questionnaire
    create_revision_of(v1)

    branch = build_revision_of(v1)

    assert_not branch.valid?, "同じ版に訂正版が並列にぶら下がれてしまいます"
    assert_includes branch.errors.full_messages, "この版は既に訂正されています"
  end

  test "訂正版を更新しても自分自身で引っかからない" do
    v2 = create_revision_of(create_questionnaire)

    assert v2.update(revision_note: "あとから理由を足す")
  end

  # ── 系列を辿る ──────────────────────────────

  test "起点・末端・全体を返す" do
    v1 = create_questionnaire
    v2 = create_revision_of(v1)
    v3 = create_revision_of(v2)

    [ v1, v2, v3 ].each(&:reload)

    assert_equal v1, v3.revision_origin
    assert_equal v1, v1.revision_origin
    assert_equal v3, v1.revision_tip
    assert_equal v3, v3.revision_tip
    assert_equal [ v1, v2, v3 ], v2.revision_chain
  end

  test "訂正が無ければ起点も末端も自分自身" do
    v1 = create_questionnaire

    assert_equal v1, v1.revision_origin
    assert_equal v1, v1.revision_tip
    assert_equal [ v1 ], v1.revision_chain
  end

  # 記入中の訂正版で施術判断が動くと、確定していない内容で可否が決まる。
  test "確定版だけを辿る末端は、下書きの訂正版の手前で止まる" do
    v1 = create_questionnaire
    v2 = create_revision_of(v1)
    draft = create_revision_of(v2, status: :draft, submitted_at: nil)

    [ v1, v2 ].each(&:reload)

    assert_equal v2, v1.finalized_revision_tip, "下書きの訂正版が末端になっています"
    assert_equal draft, v1.revision_tip, "revision_tip は下書きも含むこと"
  end

  # 読み込み済みの一覧から辿れること（カルテ一覧の N+1 回避）。
  test "確定版の末端を、渡した配列から追加クエリ無しで辿れる" do
    v1 = create_questionnaire
    v2 = create_revision_of(v1)
    v3 = create_revision_of(v2)

    all = @patient.medical_questionnaires.to_a
    origin = all.find { |q| q.id == v1.id }

    assert_no_queries do
      assert_equal v3.id, origin.finalized_revision_tip(within: all).id
    end
  end

  # ── 循環参照 ────────────────────────────────

  test "循環参照があっても辿る処理が止まる" do
    v1 = create_questionnaire
    v2 = create_revision_of(v1)
    # 検証を通さずに壊れた参照を作る（本来は作れない形）
    v1.update_column(:previous_id, v2.id)

    [ v1, v2 ].each(&:reload)

    assert_nothing_raised do
      Timeout.timeout(5) do
        v2.revision_origin
        v2.revision_tip
        v2.revision_chain
        v1.finalized_revision_tip
        v1.finalized_revision_tip(within: @patient.medical_questionnaires.to_a)
      end
    end
  end

  private

  def create_patient
    User.create!(name: "テスト患者", user_type: "2",
                 email: "revision-test-#{SecureRandom.hex(6)}@example.com",
                 password: SecureRandom.hex(12))
  end

  def create_questionnaire(**attrs)
    defaults = { status: :submitted, submitted_at: Time.current, answers: {} }
    @patient.medical_questionnaires.create!(defaults.merge(attrs))
  end

  def build_revision_of(previous, **attrs)
    defaults = { status: :submitted, submitted_at: Time.current, answers: {},
                 previous_version: previous }
    @patient.medical_questionnaires.new(defaults.merge(attrs))
  end

  def create_revision_of(previous, **attrs)
    build_revision_of(previous, **attrs).tap(&:save!)
  end

  # 追加クエリが出ないこと。読み込み済みの関連から辿っているかを見る。
  def assert_no_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }

    assert_equal 0, count, "系列を辿る段でクエリが #{count} 本出ています（一覧が N+1 になります）"
  end
end
