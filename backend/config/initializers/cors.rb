Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:5173")

    resource "*",
      headers: :any,
      expose: ["X-User-Id"],
      methods: %i[get post put patch delete options head]
  end
end
