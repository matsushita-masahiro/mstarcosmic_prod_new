# config/initializers/allow_browser_patch.rb

begin
  require "action_controller/metal/allow_browser"
  Rails.logger.info "✅ AllowBrowser loaded manually"

  module ActionController::Metal::AllowBrowser
    def self.included(base)
      Rails.logger.warn "⛔️ Skipping AllowBrowser include in #{base.name}"
    end
  end

  Rails.application.config.after_initialize do
    Rails.application.eager_load! unless Rails.configuration.cache_classes

    controllers = ObjectSpace.each_object(Class).select do |klass|
      klass < ActionController::Base && klass.respond_to?(:_process_action_callbacks)
    end

    controllers.each do |controller_class|
      removed_count = 0

      controller_class._process_action_callbacks.each do |cb|
        if cb.kind == :before &&
           cb.filter.is_a?(Proc) &&
           cb.filter.source_location&.first&.include?("allow_browser.rb")

          begin
            controller_class.skip_callback(:process_action, :before, cb.filter)
            removed_count += 1
          rescue => e
            Rails.logger.warn "❌ Failed to skip callback from #{controller_class.name}: #{e.message}"
          end
        end
      end

      Rails.logger.info "🧹 Removed #{removed_count} AllowBrowser filters from #{controller_class.name}"
    end
  end
rescue LoadError => e
  Rails.logger.error "❌ Failed to require AllowBrowser: #{e.message}"
end
