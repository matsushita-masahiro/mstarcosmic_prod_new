require_relative "boot"
require "rails/all"

# ✅ 追加（ForceHtmlForTurbo）
require_relative "../app/middleware/force_html_for_turbo"
require_relative "../app/middleware/force_html_accept_middleware" 
Bundler.require(*Rails.groups)

# 暗号化キーを ENV から読むため、Rails 初期化前に .env を確定させる
require "dotenv"
Dotenv.load(".env")

module MstarcosmicNew
  class Application < Rails::Application
    config.load_defaults 8.0
    config.i18n.default_locale = :ja
    config.middleware.insert_before ActionDispatch::Executor, ForceHtmlAcceptMiddleware
    # ✅ middleware を先頭に挿入
    config.middleware.insert_before 0, ForceHtmlForTurbo
    # 他設定
    config.autoload_paths << Rails.root.join("app/middleware")
    config.autoload_lib(ignore: %w[assets tasks])

    # ActiveRecord::Encryption の鍵。
    # このアプリは credentials を使わず .env / 各環境の環境変数で統一しているため、
    # 暗号化キーも同じ方式で渡す。
    # 鍵の生成: bin/rails runner "3.times { puts SecureRandom.alphanumeric(32) }"
    # 【重要】鍵を失うと暗号化済みデータは復号できない。パスワードマネージャに保管すること。
    if ENV["AR_ENCRYPTION_PRIMARY_KEY"].present?
      config.active_record.encryption.primary_key =
        ENV["AR_ENCRYPTION_PRIMARY_KEY"]
      config.active_record.encryption.deterministic_key =
        ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
      config.active_record.encryption.key_derivation_salt =
        ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
    end
  end
end
