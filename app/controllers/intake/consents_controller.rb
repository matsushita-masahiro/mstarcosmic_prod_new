module Intake
  class ConsentsController < BaseController
    MAX_SIGNATURE_BYTES = 2.megabytes

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

      attach_signature_image

      if @consent.save
        session[:completed_signer_name] = @consent.signer_name
        intake_session.complete!(ip: request.remote_ip, user_agent: request.user_agent)
        render json: { redirect_to: intake_thanks_path }, status: :created
      else
        render json: { errors: @consent.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def default_signer_name
      current_patient.patient_profile&.name_kana.presence ||
        current_patient.try(:name).presence || "本人"
    end

    def parsed_strokes
      raw = params[:signature_strokes]
      return nil if raw.blank?
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    # data:image/png;base64,... を ActiveStorage に取り込む
    def attach_signature_image
      data_url = params[:signature_image].to_s
      return if data_url.blank? || data_url.bytesize > MAX_SIGNATURE_BYTES

      match = data_url.match(%r{\Adata:image/png;base64,(?<payload>[A-Za-z0-9+/=\s]+)\z})
      return unless match

      binary = Base64.strict_decode64(match[:payload].gsub(/\s/, ""))
      @consent.signature_image.attach(
        io: StringIO.new(binary),
        filename: "consent_#{current_patient.id}_#{Time.current.to_i}.png",
        content_type: "image/png"
      )
    rescue ArgumentError
      nil # 不正な base64 は無視。署名なしとして validation で弾かれる
    end
  end
end
