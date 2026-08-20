# 壊れた answers のキーを直す。
#
# 【何が壊れていたか】
# questionnaire_controller.js の collectAnswers() が、input の name から
# キーを取り出すときに /^answers\[|\]$/g で先頭と末尾を同時に剥がしていた。
# 複数選択の name は "answers[q6_family_history][]" のように "][]" で
# 終わるため、末尾の "]" が1つだけ落ちて "q6_family_history][" という
# キーが jsonb に保存された。値そのものは壊れていない。
#
# コード側は修正済み。ここは既に保存されてしまったレコードを直すためのもので、
# rake intake:fix_answer_keys から呼ぶ。
#
# 【マイグレーションにしない理由】
# Procfile の release フェーズで db:migrate が自動実行されるため、
# 目視で確認する前に本番のデータへ手が入る。rake タスクにして、
# dry-run で件数と対象を確かめてから APPLY=1 で流す。
module AnswerKeyRepair
  # 壊れたキーの形。末尾の "][" だけが余分に付いている。
  BROKEN_SUFFIX = /\]\[\z/

  Result = Struct.new(:answers, :renames, :conflicts, keyword_init: true) do
    # 直すところがあるか（衝突だけの場合も「触る必要がある」ので真）
    def broken? = renames.any? || conflicts.any?

    # 実際に書き換えてよいか。衝突があるレコードは人が見るまで触らない。
    def safe_to_apply? = renames.any? && conflicts.empty?
  end

  # answers（Hash）を受け取り、直した Hash と内訳を返す。破壊的変更はしない。
  #
  # 衝突（正しいキーが既に存在する）の扱い:
  #   値が同じ    … 壊れたキーを落とすだけ。renames に含める。
  #   値が違う    … どちらが患者の回答か決められないので conflicts に入れ、
  #                 そのレコードは書き換えない。数は多くないはずなので、
  #                 機械が選ばずに人が中身を見て決める。
  def self.repair(answers)
    source = answers || {}
    renames = []
    conflicts = []
    fixed = source.dup

    source.each do |key, value|
      next unless key.match?(BROKEN_SUFFIX)

      correct = key.sub(BROKEN_SUFFIX, "")

      if source.key?(correct) && source[correct] != value
        conflicts << { broken: key, correct: correct,
                       broken_value: value, correct_value: source[correct] }
        next
      end

      fixed.delete(key)
      fixed[correct] = value
      renames << { from: key, to: correct }
    end

    Result.new(answers: fixed, renames: renames, conflicts: conflicts)
  end
end
