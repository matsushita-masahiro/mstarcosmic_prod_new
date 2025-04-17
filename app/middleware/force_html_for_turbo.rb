# app/middleware/force_html_for_turbo.rb
class ForceHtmlForTurbo
  def initialize(app)
    @app = app
  end

  def call(env)
    # SafariやCloud9環境の Accept を text/html に書き換え
    if env["HTTP_ACCEPT"] && env["HTTP_ACCEPT"].include?("application/xhtml+xml")
      env["HTTP_ACCEPT"] = "text/html"
    end
    @app.call(env)
  end
end
