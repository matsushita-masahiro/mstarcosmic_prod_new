Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("ALLOWED_ORIGINS", "http://localhost:3001").split(",")

    resource "/api/*",
      headers: :any,
      methods: %i[get post patch put delete options head]
  end
end
