require_relative "boot"
require "rails/all"

# ✅ 追加（ForceHtmlForTurbo）
require_relative "../app/middleware/force_html_for_turbo"

Bundler.require(*Rails.groups)

module MstarcosmicNew
  class Application < Rails::Application
    config.load_defaults 8.0
    config.i18n.default_locale = :ja

    # ✅ middleware を先頭に挿入
    config.middleware.insert_before 0, ForceHtmlForTurbo
    # 他設定
    config.autoload_paths << Rails.root.join("app/middleware")
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
