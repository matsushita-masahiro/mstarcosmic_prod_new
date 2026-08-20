module Intake
  # この来店ぶんの「記入中の問診票」を引く。
  #
  # 記入画面（QuestionnairesController）と確認画面
  # （QuestionnaireConfirmationsController）が必ず同じ1件を指す必要がある。
  # 絞り込み条件を2か所に書くと、確認画面が別の下書きを開いたり、
  # 署名が別のレコードに付いたりする。条件はここ1か所に置く。
  #
  # 訂正でも同じ。訂正版は「前版を指した新しい下書き」なので、
  # この scope でそのまま引ける（previous_id は記入画面が立てる）。
  module QuestionnaireDraft
    private

    def draft_scope
      current_patient.medical_questionnaires
                     .status_draft
                     .where(intake_session: intake_session)
    end
  end
end
