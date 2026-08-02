module Intake
  class ConsentsController < BaseController
    def new
      @document = ConsentDocument.current
      return redirect_to intake_expired_path if @document.nil?

      @consent = Consent.new(signer_relation: :self_signed)
    end

    def create
      @document = ConsentDocument.current
      return head :unprocessable_entity if @document.nil?

      @consent = Consent.new(
        user: current_patient,
        consent_document: @document,
        intake_session: intake_session,
        agreed_at: Time.current,
        signer_name: params[:signer_name].to_s.strip.presence || default_signer_name,
        signer_relation: :self_signed,
        signature_strokes: parsed_strokes,
        ip_address: request.remote_ip,
        user_agent: request.user_agent&.truncate(255)
      )

      if @consent.save
        # 画像は保存後に添付する（blob のキーに患者IDを含めるため）
        KarteAttachment.attach!(
          record: @consent, name: :signature_image,
          data_url: params[:signature_image],
          user_id: current_patient.id, label: "consent"
        )

        session[:completed_signer_name] = @consent.signer_name
        # トークンはまだ失効させない。問診票の提出時に失効する。
        render json: { redirect_to: intake_questionnaire_path }, status: :created
      else
        render json: { errors: @consent.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    # 署名者名は漢字の氏名を優先する。
    # カナは同意書の署名欄としては不自然なため、name が無い場合の代替に留める。
    def default_signer_name
      current_patient.name.presence || current_patient.name_kana.presence || "本人"
    end

    def parsed_strokes
      raw = params[:signature_strokes]
      return nil if raw.blank?
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end
end
