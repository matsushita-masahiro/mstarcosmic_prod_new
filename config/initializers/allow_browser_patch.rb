# config/initializers/allow_browser_patch.rb

begin
  require "action_controller/metal/allow_browser"
  Rails.logger.info "✅ AllowBrowser loaded manually"

  module ActionController::Metal::AllowBrowser
    def self.included(base)
      Rails.logger.warn "⛔️ Skipping AllowBrowser include"
    end
  end

  Rails.application.config.to_prepare do
    target_controllers = [
      ActionController::Base,
      DeviseController,
      Devise::SessionsController,
      Users::SessionsController
    ].select { |c| defined?(c) }

    target_controllers.each do |controller_class|
      if controller_class.respond_to?(:_process_action_callbacks)
        callbacks = controller_class._process_action_callbacks
        before_count = callbacks.send(:chain).length

        callbacks.send(:chain).delete_if do |cb|
          cb.filter.is_a?(Proc) &&
            cb.filter.source_location&.first&.include?("allow_browser.rb")
        end

        after_count = callbacks.send(:chain).length
        Rails.logger.info "🧹 Removed #{before_count - after_count} AllowBrowser filters from #{controller_class.name}"
      end
    end
  end

rescue LoadError => e
  Rails.logger.error "❌ Failed to require AllowBrowser: #{e.message}"
rescue => e
  Rails.logger.error "❌ Unexpected error: #{e.class} - #{e.message}"
end
