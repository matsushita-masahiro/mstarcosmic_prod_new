module Intake
  class QuestionnairesController < BaseController
    def show
      return redirect_to new_intake_consent_path unless Consent.current_for?(current_patient)

      @questionnaire = find_or_build_draft
      @questions = MedicalQuestionnaireForm::QUESTIONS

      # users.gender があればそれを使い、無ければ問診票の冒頭で聞く
      @gender_known = current_patient.gender_known?
      @is_female = current_patient.female?
    end

    def update
      questionnaire = find_or_build_draft
      questionnaire.answers = parsed_answers
      questionnaire.save!

      render json: { saved_at: Time.current.iso8601 }
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def create
      questionnaire = find_or_build_draft
      questionnaire.answers = parsed_answers

      ActiveRecord::Base.transaction do
        questionnaire.save!
        save_handwriting_entries(questionnaire)
        save_body_marks(questionnaire)
        questionnaire.submit!(intake_session: intake_session)
        sync_gender_if_needed(questionnaire)
      end

      intake_session.complete!(ip: request.remote_ip, user_agent: request.user_agent)
      session[:completed_signer_name] = current_patient.name_kana

      render json: { redirect_to: intake_thanks_path }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def find_or_build_draft
      current_patient.medical_questionnaires
                     .status_draft
                     .where(intake_session: intake_session)
                     .first_or_initialize(
                       form_version: MedicalQuestionnaireForm::VERSION,
                       intake_session: intake_session
                     )
    end

    def parsed_answers
      raw = params[:answers]
      return {} if raw.blank?
      raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    rescue JSON::ParserError
      {}
    end

    # 問診票で性別を聞いた場合、users 側が未設定なら反映する。
    # 既に値がある場合は上書きしない（患者の自己申告より既存データを優先）。
    def sync_gender_if_needed(questionnaire)
      return if current_patient.gender.present?

      answer = questionnaire.answers["q0_gender"]
      return if answer.blank?

      current_patient.update_column(:gender, answer == "female" ? "f" : "m")
    end

    def save_handwriting_entries(questionnaire)
      entries = parse_json_param(:handwriting)
      return if entries.blank?

      entries.each do |key, data|
        next unless MedicalQuestionnaireForm.handwriting_keys.include?(key)

        entry = questionnaire.handwriting_entries.find_or_initialize_by(question_key: key)
        entry.input_mode = data["mode"] == "keyboard" ? :keyboard : :pen

        if entry.input_mode_keyboard?
          entry.transcribed_text = data["text"].to_s
          entry.strokes = []
        else
          entry.strokes = data["strokes"] || []
          entry.canvas_width  = data["width"]
          entry.canvas_height = data["height"]
        end

        entry.save!

        # 画像は保存後に添付する（blob のキーに患者IDを含めるため）
        next if entry.input_mode_keyboard?
        KarteAttachment.attach!(
          record: entry, name: :image, data_url: data["image"],
          user_id: current_patient.id, label: key
        )
      end
    end

    def save_body_marks(questionnaire)
      marks = parse_json_param(:body_marks)
      return if marks.blank?

      questionnaire.body_marks.destroy_all
      marks.each do |m|
        x = m["x"].to_f
        y = m["y"].to_f
        next unless x.between?(0, 1) && y.between?(0, 1)

        questionnaire.body_marks.create!(
          side: m["side"] == "back" ? :back : :front,
          x: x, y: y,
          mark_type: %w[pain numbness stiffness other].include?(m["mark_type"]) ? m["mark_type"] : "pain",
          note: m["note"].presence
        )
      end
    end

    def parse_json_param(name)
      raw = params[name]
      return nil if raw.blank?
      raw.is_a?(String) ? JSON.parse(raw) : raw
    rescue JSON::ParserError
      nil
    end
  end
end
