require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # ステージ / 本番でバケットを分ける（KARTE_STORAGE_SERVICE で指定）
  config.active_storage.service = ENV.fetch("KARTE_STORAGE_SERVICE", "karte_prod").to_sym

  # 署名画像はコントローラ経由で配信し、認証を通せるようにする
  # （デフォルトの redirect 方式だと URL を知る者は誰でも閲覧できてしまう）
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # 署名・手書き画像に metadata 解析は不要。
  # 解析すると ActiveStorage::AnalyzeJob が enqueue され、
  # Solid Queue 未整備の環境で 500 になる。
  config.active_storage.analyzers = []

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # ActiveJob は同期実行（:inline）。Solid Queue は導入しない。
  #
  # solid_queue_* のテーブルが無い状態で :solid_queue を指定していたため、
  # 添付を持つレコードの destroy で ActiveStorage::PurgeJob の enqueue が
  # PG::UndefinedTable で落ちていた。しかも after_commit のため DELETE は
  # コミット済みで、「削除は成功したのに例外が上がる」状態だった。
  # 非同期にしたいジョブが他に無いため、:inline に固定する。
  config.active_job.queue_adapter = :inline
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }
  
  config.action_mailer.default_url_options = { :host => 'https://www.mstarcosmic.com' }  
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
      port:                 587,
      address:              'mail92.onamae.ne.jp',
      domain:               'ne.jp',
      user_name:           ENV['USER_EMAIL'],
      password:            ENV['EMAIL_PASSWORD'],
      authentication:       'plain',
      enable_starttls_auto: true
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
