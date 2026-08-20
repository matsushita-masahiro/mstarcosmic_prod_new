module Intake
  class ConsentsController < BaseController
    def new
      # 署名済みなら書かせない。入口（sessions#show）で振り分けているが、
      # 戻るボタンや URL 直打ちでここへ来られる。そこで署名させると
      # 同意書レコードが増える。
      return redirect_to intake_questionnaire_path if Consent.current_for?(current_patient)

      @document = ConsentDocument.current
      return redirect_to intake_expired_path if @document.nil?

      @consent = Consent.new(signer_relation: :self_signed)
    end

    def create
      # 既に署名済みなら作らない。
      #
      # 画面を出さないようにしても、開いたまま放置された同意書画面から
      # 送信される経路が残る（別端末で先に署名を済ませた場合など）。
      # 患者にエラーを見せる意味は無いので、成功時と同じ形で問診票へ送る。
      # 署名し直したぶんは捨てるが、有効な署名は既にサーバにある。
      if Consent.current_for?(current_patient)
        return render json: { redirect_to: intake_questionnaire_path }
      end

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
