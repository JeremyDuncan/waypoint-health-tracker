class MetricDefinitions
  def self.format_value(key, value)
    unit = ALL.fetch(key).fetch("unit")
    return value.to_s if unit == "text"
    unit == "0–10" ? "#{value}/10" : "#{value} #{unit}"
  end

  ALL = {
    "appetite" => { "label" => "Appetite", "unit" => "0–10", "min" => 0, "max" => 10 },
    "side_effects" => { "label" => "Side effects", "unit" => "text" },
    "severity" => { "label" => "Side effect severity", "unit" => "0–10", "min" => 0, "max" => 10 },
    "waist_cm" => { "label" => "Waist circumference", "unit" => "cm", "min" => 1, "max" => 400 },
    "systolic" => { "label" => "Blood pressure · systolic", "unit" => "mmHg", "min" => 40, "max" => 300 },
    "diastolic" => { "label" => "Blood pressure · diastolic", "unit" => "mmHg", "min" => 20, "max" => 200 },
    "resting_heart_rate" => { "label" => "Resting heart rate", "unit" => "bpm", "min" => 20, "max" => 250 },
    "sleep_hours" => { "label" => "Sleep duration", "unit" => "hours", "min" => 0, "max" => 24 }
  }.freeze
end
