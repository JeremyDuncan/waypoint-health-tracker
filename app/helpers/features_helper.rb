module FeaturesHelper
  def chart_range_label(range)
    { "7" => "7 days", "30" => "30 days", "90" => "90 days", "365" => "1 year", "all" => "All time", "custom" => "Custom dates" }.fetch(range)
  end
  def percent_loss_label(value)
    return "—" if value.nil?
    rounded = value.round(1)
    direction = rounded.negative? ? "lost" : rounded.positive? ? "gained" : "change"
    "#{number_with_precision(value.abs, precision: 1)}% #{direction}"
  end

  def plot_area_path(plot, offset: 0)
    return "" if plot.points.size < 2
    plot_path(plot, offset: offset) + " L#{40 + plot.points.last[:x] * 640},#{210 + offset} L#{40 + plot.points.first[:x] * 640},#{210 + offset} Z"
  end
  def metric_number(value, unit = current_user.preferred_unit)
    return "—" if value.nil?
    number = number_with_precision(value, precision: 1)
    unit == "0–10" ? "#{number}/10" : "#{number} #{unit}"
  end

  def plot_path(plot, offset: 0)
    return "" if plot.points.empty?
    first = plot.points.first
    path = "M#{40 + first[:x] * 640},#{210 + offset - first[:y] * 160}"
    SmoothLine.segments(plot.points).each do |segment|
      path += " C" + (segment[:controls] + [segment[:to]]).map { |point| "#{40 + point[:x] * 640},#{210 + offset - point[:y] * 160}" }.join(" ")
    end
    path
  end
end
