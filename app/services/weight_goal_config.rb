class WeightGoalConfig
  include ActiveModel::Model
  attr_accessor :mode, :value, :unit, :start_date, :low, :high
  FIELDS = %w[mode value unit start_date low high].freeze
  validates :mode, inclusion: { in: %w[target maintenance] }
  validates :unit, inclusion: { in: %w[lb kg] }
  validate do
    begin
      Date.iso8601(start_date.to_s)
      raise ArgumentError unless start_date.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    rescue ArgumentError
      errors.add(:start_date, "must be a valid calendar date")
    end
    fields = mode == "maintenance" ? %w[low high] : %w[value]
    fields.each do |field|
      number = BigDecimal(public_send(field).to_s, exception: false)
      errors.add(field, "must be a positive weight up to 1500 with at most four decimal places") unless number&.finite? && number > 0 && number <= 1500 && number == number.round(4)
    end
    if mode == "maintenance" && errors[:low].empty? && errors[:high].empty? && BigDecimal(low.to_s) > BigDecimal(high.to_s)
      errors.add(:high, "must be at least the lower weight")
    end
  end

  def portable
    FIELDS.to_h { |key| [key, public_send(key).presence] }.merge(
      "value" => mode == "target" ? BigDecimal(value.to_s).to_s("F") : nil,
      "low" => mode == "maintenance" ? BigDecimal(low.to_s).to_s("F") : nil,
      "high" => mode == "maintenance" ? BigDecimal(high.to_s).to_s("F") : nil)
  end
end
