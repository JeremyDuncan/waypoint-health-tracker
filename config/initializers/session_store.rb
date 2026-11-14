# Retain the original cookie name so the branding change preserves existing sessions.
Rails.application.config.session_store :cookie_store, key: "_hearth", httponly: true,
  same_site: :lax, secure: Rails.env.production? && ENV.fetch("FORCE_SSL", "true") == "true"
