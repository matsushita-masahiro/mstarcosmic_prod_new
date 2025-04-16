# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# ✅ ここから monkey patch
begin
  require_relative "config/environment"
  require "action_controller/metal/allow_browser"
  module ActionController::Metal::AllowBrowser
    def self.included(base)
      puts "⛔️ AllowBrowser inclusion skipped from config.ru"
    end
  end
rescue => e
  puts "❌ AllowBrowser patch failed in config.ru: #{e.message}"
end
# ✅ ここまで monkey patch



run Rails.application
Rails.application.load_server
