# app/services/karte_attachment.rb
#
# カルテ関連の画像を、患者ごと・年月ごとに階層化したキーで S3 に保存する。
#
#   KarteAttachment.attach!(
#     record: consent, name: :signature_image,
#     data_url: params[:signature_image],
#     user_id: current_patient.id, label: "consent"
#   )
#
# data_url は "data:image/png;base64,..." 形式を想定する。
class KarteAttachment
  MAX_BYTES = 3.megabytes
  PNG_DATA_URL = %r{\Adata:image/png;base64,(?<payload>[A-Za-z0-9+/=\s]+)\z}

  class << self
    def attach!(record:, name:, data_url:, user_id:, label:)
      binary = decode_png(data_url)
      return false if binary.nil?

      blob = ActiveStorage::Blob.new(
        filename: "#{label}.png",
        content_type: "image/png",
        byte_size: binary.bytesize,
        checksum: OpenSSL::Digest::MD5.base64digest(binary)
      )
      blob.karte_context = { user_id: user_id, label: label }
      blob.upload_without_unfurling(StringIO.new(binary))
      blob.save!

      record.public_send(name).attach(blob)
      true
    rescue StandardError => e
      Rails.logger.error("[KarteAttachment] #{e.class}: #{e.message}")
      false
    end

    private

    def decode_png(data_url)
      return nil if data_url.blank? || data_url.bytesize > MAX_BYTES

      match = data_url.match(PNG_DATA_URL)
      return nil unless match

      Base64.strict_decode64(match[:payload].gsub(/\s/, ""))
    rescue ArgumentError
      nil
    end
  end
end
