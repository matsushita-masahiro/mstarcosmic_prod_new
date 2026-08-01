module Intake
  class QuestionnairesController < BaseController
    MAX_IMAGE_BYTES = 3.megabytes

    def show
      # 同意書に署名していない場合は先に同意書へ
      return redirect_to new_intake_consent_path unless Consent.current_for?(current_patient)

      @questionnaire = current_patient.medical_questionnaires
                                      .status_draft
                                      .where(intake_session: intake_session)
                                      .first_or_initialize(form_version: MedicalQuestionnaireForm::VERSION)
      @questions = MedicalQuestionnaireForm::QUESTIONS
    end

    # 下書き保存（30秒ごとの自動保存 + 明示的な保存）
    def update
      questionnaire = find_or_build_draft
      questionnaire.answers = parsed_answers
      questionnaire.save!

      render json: { saved_at: Time.current.iso8601 }
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    # 最終提出
    def create
      questionnaire = find_or_build_draft
      questionnaire.answers = parsed_answers

      ActiveRecord::Base.transaction do
        questionnaire.save!
        save_handwriting_entries(questionnaire)
        save_body_marks(questionnaire)
        questionnaire.submit!(intake_session: intake_session)
      end

      intake_session.complete!(ip: request.remote_ip, user_agent: request.user_agent)
      session[:completed_signer_name] = current_patient.patient_profile&.name_kana

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

    # 自由記述欄。ペン入力なら strokes + PNG、キーボード入力なら text。
    def save_handwriting_entries(questionnaire)
      entries = parse_json_param(:handwriting)
      return if entries.blank?

      entries.each do |key, data|
        next unless MedicalQuestionnaireForm.handwriting_keys.include?(key)

        entry = questionnaire.handwriting_entries.find_or_initialize_by(question_key: key)
        entry.input_mode = data["mode"] == "keyboard" ? :keyboard : :pen

        if entry.input_mode == "keyboard"
          entry.transcribed_text = data["text"].to_s
          entry.strokes = []
        else
          entry.strokes = data["strokes"] || []
          entry.canvas_width  = data["width"]
          entry.canvas_height = data["height"]
          attach_png(entry, data["image"])
        end

        entry.save!
      end
    end

    # 人体図のマーク。相対座標（0.0〜1.0）で保存し解像度に依存させない。
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

    def attach_png(entry, data_url)
      return if data_url.blank? || data_url.bytesize > MAX_IMAGE_BYTES

      match = data_url.match(%r{\Adata:image/png;base64,(?<payload>[A-Za-z0-9+/=\s]+)\z})
      return unless match

      binary = Base64.strict_decode64(match[:payload].gsub(/\s/, ""))
      entry.image.attach(
        io: StringIO.new(binary),
        filename: "#{entry.question_key}_#{Time.current.to_i}.png",
        content_type: "image/png"
      )
    rescue ArgumentError
      nil
    end
  end
end
