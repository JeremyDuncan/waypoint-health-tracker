class Injection < ApplicationRecord
  include TimedRecord
  validates :dose, inclusion: { in: [2.5, 5, 7.5, 10, 12.5, 15] }
  validates :site, inclusion: { in: [nil, "", "Abdomen", "Thigh", "Upper arm"] }
  validates :side, inclusion: { in: [nil, "", "Left", "Right"] }
  validates :notes, length: { maximum: 10000 }
  def portable
    { "id" => uuid, "occurred_at" => occurred_at, "dose" => dose.to_s("F"), "site" => site, "side" => side, "notes" => notes }
  end
end
