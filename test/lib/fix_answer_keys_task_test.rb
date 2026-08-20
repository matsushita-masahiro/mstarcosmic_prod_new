require "test_helper"
require "rake"

# rake intake:fix_answer_keys の書き込み側。
#
# キーの直し方そのものは AnswerKeyRepair 側で見ている。
# ここで守るのは「dry-run が既定であること」と「衝突を勝手に直さないこと」。
# 本番の患者データに直接手を入れるタスクなので、既定が書き込みに変わる
# 事故だけは絶対に通さない。
class FixAnswerKeysTaskTest < ActiveSupport::TestCase
  TASK = "intake:fix_answer_keys".freeze

  setup do
    @original_apply = ENV["APPLY"]
    ENV.delete("APPLY")

    # rake ファイルの読み込みはプロセスに1回だけ。毎回 clear して読み直すと、
    # 同じプロセスで走る他のテストからタスクが消える。
    # silence_warnings は gem 側の rake ファイルが二重に読まれて出す
    # 「already initialized constant」を止めるためだけのもの。
    unless Rake::Task.task_defined?(TASK)
      silence_warnings { Rails.application.load_tasks }
    end

    @patient = User.create!(email: "fix-keys@example.com", name: "患者", password: "password")
  end

  teardown do
    @original_apply.nil? ? ENV.delete("APPLY") : ENV["APPLY"] = @original_apply
  end

  test "既定では書き込まない" do
    record = make(answers: { "q6_family_history][" => %w[糖尿病] })

    run_task

    assert_equal({ "q6_family_history][" => %w[糖尿病] }, record.reload.answers,
                 "APPLY を付けていないのに書き換わっています")
  end

  test "APPLY=1 で壊れたキーを直す" do
    record = make(answers: { "q6_family_history][" => %w[糖尿病 癌],
                             "q10_pacemaker" => "no" })

    ENV["APPLY"] = "1"
    run_task

    assert_equal({ "q10_pacemaker" => "no", "q6_family_history" => %w[糖尿病 癌] },
                 record.reload.answers)
  end

  test "訂正版も対象に含める" do
    previous = make(answers: { "q6_family_history][" => %w[糖尿病] }, status: :submitted,
                    submitted_at: 1.day.ago)
    revision = make(answers: { "q6_family_history][" => %w[糖尿病 癌] }, status: :submitted,
                    submitted_at: Time.current, previous_version: previous)

    ENV["APPLY"] = "1"
    run_task

    assert_equal %w[糖尿病], previous.reload.answers["q6_family_history"]
    assert_equal %w[糖尿病 癌], revision.reload.answers["q6_family_history"],
                 "訂正版を除くと、差分に実際には起きていない変更が出る"
  end

  test "更新日時を動かさない" do
    record = make(answers: { "q6_family_history][" => %w[糖尿病] })
    before = record.reload.updated_at

    ENV["APPLY"] = "1"
    run_task

    assert_equal before, record.reload.updated_at,
                 "提出済みの記録の更新日時は患者・スタッフの操作を表すもので、" \
                 "キーの修復で動かしてはいけない"
  end

  test "正しいキーと値が食い違うレコードは触らない" do
    conflicted = make(answers: { "q6_family_history][" => %w[糖尿病],
                                 "q6_family_history" => %w[心臓病] })
    normal = make(answers: { "q15_items][" => %w[整体] })

    ENV["APPLY"] = "1"
    run_task

    assert_equal({ "q6_family_history][" => %w[糖尿病], "q6_family_history" => %w[心臓病] },
                 conflicted.reload.answers,
                 "どちらが患者の回答か決められないレコードを機械が選んでいます")
    assert_equal({ "q15_items" => %w[整体] }, normal.reload.answers,
                 "衝突した1件のせいで、直せるレコードまで止まっています")
  end

  private

  def make(answers:, status: :submitted, submitted_at: Time.current, previous_version: nil)
    MedicalQuestionnaire.create!(
      user: @patient, answers: answers, status: status, submitted_at: submitted_at,
      form_version: MedicalQuestionnaireForm::VERSION, previous_version: previous_version
    )
  end

  def run_task
    capture_io { Rake::Task[TASK].tap(&:reenable).invoke }
  end
end
