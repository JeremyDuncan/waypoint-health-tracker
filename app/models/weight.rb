class Weight < ApplicationRecord
  include TimedRecord
  validates :value, numericality: { greater_than: 0, less_than_or_equal_to: 1500 }
  validates :unit, inclusion: { in: %w[lb kg] }
  validate do
    original = BigDecimal(value_before_type_cast.to_s, exception: false)
    errors.add(:value, "supports at most four decimal places") if original && original.finite? && original != original.round(4)
  end
  def in_unit(target)
    return value.to_f if target == unit
    target == "kg" ? value.to_f * 0.45359237 : value.to_f / 0.45359237
  end
  def portable
    { "id" => uuid, "occurred_at" => occurred_at, "value" => value.to_s("F"), "unit" => unit }
  end
end
