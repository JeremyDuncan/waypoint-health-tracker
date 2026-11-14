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

  # Geometry defaults match the 720-wide desktop figure; the phone figure passes its own.
  def plot_area_path(plot, offset: 0, left: 40, width: 640, base: 210, height: 160)
    return "" if plot.points.size < 2
    plot_path(plot, offset: offset, left: left, width: width, base: base, height: height) + " L#{left + plot.points.last[:x] * width},#{base + offset} L#{left + plot.points.first[:x] * width},#{base + offset} Z"
  end
  # 177.8 cm -> "70"; 180 cm -> "70.87"
  def height_in_inches(height_cm)
    number_with_precision(height_cm / BigDecimal("2.54"), precision: 2, strip_insignificant_zeros: true)
  end
  def metric_number(value, unit = current_user.preferred_unit)
    return "—" if value.nil?
    number = number_with_precision(value, precision: 1)
    unit == "0–10" ? "#{number}/10" : "#{number} #{unit}"
  end

  def plot_path(plot, offset: 0, left: 40, width: 640, base: 210, height: 160)
    return "" if plot.points.empty?
    position = ->(point) { "#{left + point[:x] * width},#{base + offset - point[:y] * height}" }
    path = "M#{position.(plot.points.first)}"
    SmoothLine.segments(plot.points).each do |segment|
      path += " C" + (segment[:controls] + [segment[:to]]).map(&position).join(" ")
    end
    path
  end
end
