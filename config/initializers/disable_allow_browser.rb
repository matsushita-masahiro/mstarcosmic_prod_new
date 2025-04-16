# 明示的にロード（まだされていなければ）
begin
  require "action_controller/metal/allow_browser"
  Rails.logger.info "✅ AllowBrowser loaded manually"
rescue LoadError
  Rails.logger.warn "❌ AllowBrowser could not be loaded"
end

# AllowBrowser モジュールの再定義によってフィルターを回避
module ActionController::Metal::AllowBrowser
  def self.included(base)
    Rails.logger.warn "⛔️ Skipping AllowBrowser inclusion"
    # 何もしないことで before_action をスキップ
  end
end
