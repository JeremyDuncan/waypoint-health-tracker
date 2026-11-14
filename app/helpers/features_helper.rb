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
  # One smooth curve runs through any estimated edge points and every actual
  # reading, so the dashed estimates bend into the solid line without corners.
  def plot_area_path(plot, **geometry)
    outline = plot.area_points
    return "" if outline.size < 2
    position = plot_position(**geometry)
    left, width, base = geometry.fetch(:left, 40), geometry.fetch(:width, 640), geometry.fetch(:base, 210) + geometry.fetch(:offset, 0)
    path = "M#{position.(outline.first)}" + plot_curve(plot).map { |segment| plot_segment(segment, position) }.join
    path + " L#{left + outline.last[:x] * width},#{base} L#{left + outline.first[:x] * width},#{base} Z"
  end

  # Dashed curve pieces between an estimated edge point and the nearest reading.
  def plot_estimate_path(plot, **geometry)
    position = plot_position(**geometry)
    plot_curve(plot).select { |segment| plot_estimate?(segment) }.map { |segment| "M#{position.(segment[:from])}" + plot_segment(segment, position) }.join(" ")
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

  def plot_path(plot, **geometry)
    return "" if plot.points.empty?
    position = plot_position(**geometry)
    "M#{position.(plot.points.first)}" + plot_curve(plot).reject { |segment| plot_estimate?(segment) }.map { |segment| plot_segment(segment, position) }.join
  end

  private

  def plot_position(offset: 0, left: 40, width: 640, base: 210, height: 160)
    ->(point) { "#{left + point[:x] * width},#{base + offset - point[:y] * height}" }
  end

  def plot_curve(plot) = SmoothLine.segments(plot.area_points)
  def plot_estimate?(segment) = !segment[:from].key?(:weight) || !segment[:to].key?(:weight)
  def plot_segment(segment, position) = " C" + (segment[:controls] + [segment[:to]]).map(&position).join(" ")
end
