require "csv"
class PersonalExport
  FIELDS = {
    "weights" => %w[id occurred_at value unit],
    "injections" => %w[id occurred_at dose site side notes],
    "day_notes" => %w[id local_date notes metrics]
  }.freeze
  def initialize(user) = @user = user
  def document
    { "schema" => "waypoint-health.personal", "version" => 1, "exported_at" => Time.current.iso8601,
      "preferences" => @user.preferences, "metric_definitions" => MetricDefinitions::ALL,
      "records" => FIELDS.keys.to_h { |kind| [kind, @user.public_send(kind).order(:id).map(&:portable)] } }
  end
  def csv(kind)
    fields = FIELDS.fetch(kind)
    CSV.generate(encoding: "UTF-8") do |csv|
      csv << fields
      @user.public_send(kind).order(:id).each do |record|
        attrs = record.portable
        csv << fields.map { |f| attrs[f].is_a?(Hash) ? JSON.generate(attrs[f]) : attrs[f] }
      end
    end
  end
end
