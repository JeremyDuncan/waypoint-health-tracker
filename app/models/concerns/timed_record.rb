module TimedRecord
  extend ActiveSupport::Concern
  included do
    include StableRecord
    belongs_to :user
    before_validation :parse_timestamp
    validates :occurred_at, presence: true
  end
  def parse_timestamp
    unless occurred_at.to_s.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/)
      errors.add(:occurred_at, "needs an ISO 8601 timestamp with an explicit offset")
      return
    end
    Date.iso8601(occurred_at[0, 10])
    parsed = Time.iso8601(occurred_at)
    raise ArgumentError if parsed.utc_offset.abs > 14.hours
    self.recorded_at = parsed
  rescue ArgumentError
    errors.add(:occurred_at, "is invalid")
  end
  def local_day
    recorded_at.in_time_zone(user.time_zone).to_date
  end
end
