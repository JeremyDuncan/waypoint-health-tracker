module InjectionsHelper
  def change_label(value, unit = current_user.preferred_unit)
    return "—" if value.nil?
    formatted = number_with_precision(value.abs, precision: 1)
    sign = value.round(1).negative? ? "−" : value.round(1).positive? ? "+" : ""
    "#{sign}#{formatted} #{unit}"
  end

  def change_class(value)
    return "change-neutral" if value.nil? || value.round(1).zero?
    value.negative? ? "change-down" : "change-up"
  end

  def injection_status(row)
    { complete: "Completed window", open: "In progress", no_baseline: "Baseline missing",
      no_followup: "Follow-up missing", short: "Under 24 hours", future: "Future-dated log" }.fetch(row[:status])
  end

  # "dose-2-5" or "dose-10": selects the dose's color in the stylesheet.
  def dose_class(dose) = "dose-#{dose.to_s('F').delete_suffix('.0').tr('.', '-')}"
  def dose_dot(dose) = tag.span(class: "dose-dot #{dose_class(dose)}", aria: { hidden: true })

  def site_class(site)
    { "Abdomen" => "site-abdomen", "Thigh" => "site-thigh", "Upper arm" => "site-arm" }.fetch(site, "site-unknown")
  end
end
