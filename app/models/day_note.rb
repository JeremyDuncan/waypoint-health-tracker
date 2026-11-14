class DayNote < ApplicationRecord
  include StableRecord
  belongs_to :user
  validates :local_date, presence: true, uniqueness: { scope: :user_id }
  validates :notes, length: { maximum: 10000 }
  validate do
    unless metrics.is_a?(Hash)
      errors.add(:metrics, "must be an object")
      next
    end
    metrics.each do |key, value|
      definition = MetricDefinitions::ALL[key]
      if !definition
        errors.add(:metrics, "contains unknown metric #{key}")
      elsif key == "side_effects"
        errors.add(:metrics, "side effects must be text of at most 2000 characters") unless value.is_a?(String) && value.length <= 2000
      else
        number = Float(value, exception: false)
        unless number && number.finite? && number.between?(definition["min"], definition["max"])
          errors.add(:metrics, "#{definition['label']} must be #{definition['min']}–#{definition['max']} #{definition['unit']}")
        end
      end
    end
  end
  def portable
    { "id" => uuid, "local_date" => local_date.iso8601, "notes" => notes, "metrics" => metrics }
  end
end
