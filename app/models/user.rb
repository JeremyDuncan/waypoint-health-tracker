class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :weights, dependent: :destroy
  has_many :injections, dependent: :destroy
  has_many :day_notes, dependent: :destroy
  has_many :import_batches, dependent: :destroy
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12, maximum: 72 }, allow_nil: true
  validates :password, :password_confirmation, presence: true, on: :password_change
  validates :preferred_unit, inclusion: { in: %w[lb kg] }
  validates :height_cm, numericality: { greater_than: 0, less_than_or_equal_to: 300 }, allow_nil: true
  validate do
    errors.add(:time_zone, "must be a known IANA timezone") unless ActiveSupport::TimeZone[time_zone]
    errors.add(:enabled_metrics, "contains an unknown metric") unless enabled_metrics.is_a?(Array) && (enabled_metrics - MetricDefinitions::ALL.keys).empty?
    begin
      ChartPreferences.validate_document!(chart_preferences)
    rescue ArgumentError, Date::Error => error
      errors.add(:chart_preferences, error.message)
    end
    unless weight_goal.nil?
      if !weight_goal.is_a?(Hash) || weight_goal.keys.sort != WeightGoalConfig::FIELDS.sort
        errors.add(:weight_goal, "has unsupported fields")
      else
        goal = WeightGoalConfig.new(weight_goal)
        errors.add(:weight_goal, goal.errors.full_messages.join("; ")) unless goal.valid?
      end
    end
  end
  def preferences
    { "preferred_unit" => preferred_unit, "time_zone" => time_zone, "enabled_metrics" => enabled_metrics,
      "reminder_at" => reminder_at&.iso8601, "weight_goal" => weight_goal, "height_cm" => height_cm&.to_s("F"), "chart_preferences" => chart_preferences }
  end
end
