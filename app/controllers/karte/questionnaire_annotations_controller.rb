module Karte
  # 問診票へのスタッフ追記。
  #
  # 追加専用。update / destroy は作らない（ルートも引いていない）。
  # 書き間違いは訂正の追記を足す運用で、モデル側も readonly? で止めている。
  #
  # 権限は BaseController の authenticate_staff_user? に任せる。
  # 「書ける人＝カルテを見られる人」で、追記のために新しい判定は作らない。
  class QuestionnaireAnnotationsController < BaseController
    before_action :set_patient
    before_action :set_questionnaire

    def create
      @annotation = @questionnaire.questionnaire_annotations.new(annotation_params)
      # 書いた人はログイン中の本人。パラメータからは受け取らない。
      # 受け取ると、他のスタッフの名前で申し送りを書けてしまう。
      @annotation.staff = current_user

      if @annotation.save
        log_access!(patient: @patient, action: "annotation_create", resource: @annotation)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_back_to_karte(notice: "追記を保存しました。") }
        end
      else
        redirect_back_to_karte(alert: @annotation.errors.full_messages.join(" / "))
      end
    end

    private

    def set_patient
      @patient = User.find(params[:user_id])
    end

    # 患者の持ち物だけを対象にする。問診票の id だけで引くと、
    # URL を差し替えて他人の問診票に追記できてしまう。
    def set_questionnaire
      @questionnaire = @patient.medical_questionnaires
                               .find(params.dig(:questionnaire_annotation, :medical_questionnaire_id))
    end

    # question_key はパラメータで受けるが、設問定義との照合は
    # モデルのバリデーションが行う（QuestionnaireAnnotation）。
    def annotation_params
      params.require(:questionnaire_annotation).permit(:question_key, :body)
    end

    # 追記した設問の位置に戻す。表示中の版を保つため questionnaire_id を付ける。
    def redirect_back_to_karte(**flash_args)
      redirect_to karte_user_path(@patient, questionnaire_id: @questionnaire.id), **flash_args
    end
  end
end
