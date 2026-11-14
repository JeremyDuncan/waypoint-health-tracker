module ApplicationHelper
  def weight_label(weight)
    "#{number_with_precision(weight.value, precision: 2, strip_insignificant_zeros: true)} #{weight.unit}"
  end
  def local_time_label(time)
    time.in_time_zone.strftime("%b %-d, %Y · %-I:%M %p %Z")
  end
  def errors_for(record)
    return if record.errors.empty?
    content_tag(:div, class: "errors", role: "alert") do
      safe_join(record.errors.full_messages.map { |message| content_tag(:p, message) })
    end
  end
end
