Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"
  config.assume_ssl = config.force_ssl
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
  config.public_file_server.headers = { "cache-control" => "public, max-age=31536000" }
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = :warn
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false
  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]
  config.hosts = ENV.fetch("APP_HOST", "localhost").split(",")
  config.host_authorization = { exclude: ->(r) { r.path == "/up" } }
  config.cache_store = :memory_store, { size: 8 * 1024 * 1024 }
end
