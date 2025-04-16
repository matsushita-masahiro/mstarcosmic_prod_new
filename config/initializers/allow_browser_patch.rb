# config/initializers/allow_browser_patch.rb

begin
  require "action_controller/metal/allow_browser"
  Rails.logger.info "✅ AllowBrowser loaded manually"

  # includeを空定義（これでbefore_actionを登録させない）
  module ActionController::Metal::AllowBrowser
    def self.included(base)
      Rails.logger.warn "⛔️ Skipping AllowBrowser include"
    end
  end
rescue LoadError => e
  Rails.logger.error "❌ Failed to require AllowBrowser: #{e.message}"
end

# after_initialize で Devise も含めて確実に読み込まれた後に実行
Rails.application.config.after_initialize do
  begin
    # Devise関連などのControllerを含めて一括で処理
    target_controllers = ObjectSpace.each_object(Class).select do |klass|
      klass < ActionController::Base && klass.respond_to?(:_process_action_callbacks)
    end

    target_controllers.each do |controller_class|
      removed = controller_class._process_action_callbacks.delete_if do |cb|
        cb.filter.is_a?(Proc) &&
          cb.filter.source_location&.first&.include?("allow_browser.rb")
      end

      if removed
        Rails.logger.info "🧹 Removed AllowBrowser filter from #{controller_class.name}"
      end
    end
  rescue => e
    Rails.logger.error "❌ Error while removing AllowBrowser filters: #{e.message}"
  end
end
