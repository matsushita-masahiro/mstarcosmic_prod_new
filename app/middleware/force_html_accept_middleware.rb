# app/middleware/force_html_accept_middleware.rb
class ForceHtmlAcceptMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Safari などの Accept ヘッダーが原因で AllowBrowser が406返すのを防ぐ
    env["HTTP_ACCEPT"] = "text/html" if env["PATH_INFO"].start_with?("/users/sign_in")
    @app.call(env)
  end
end
