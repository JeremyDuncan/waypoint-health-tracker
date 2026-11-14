class WeightPlot
  attr_reader :points, :injections, :minimum, :maximum, :days, :estimates

  # `before`/`after` are optional readings just outside the range. When given,
  # the line is extended to the range edges with straight-line estimates
  # between the nearest readings on either side; those are never measurements.
  def initialize(range, unit, display_to: range.to, before: nil, after: nil)
    start = range.from.in_time_zone.to_f
    finish = (display_to + 1).in_time_zone.to_f
    span = finish - start
    inside = range.weights
    estimated = {}
    if before && (following = inside.first || after)
      estimated[:start] = interpolate(before, following, start, unit)
    end
    if after && (preceding = inside.last || before)
      estimated[:end] = interpolate(preceding, after, finish, unit)
    end
    values = inside.map { |weight| weight.in_unit(unit) } + estimated.values
    @minimum = values.min || 0
    @maximum = values.max || 1
    padding = [(@maximum - @minimum) * 0.12, 0.5].max
    @minimum -= padding
    @maximum += padding
    scale = ->(value) { (value - minimum) / (maximum - minimum) }
    @estimates = estimated.to_h { |edge, value| [edge, { x: edge == :start ? 0.0 : 1.0, y: scale.(value), value: value }] }
    @days = (display_to - range.from).to_i < 14 ? (range.from..display_to).map { |day| { date: day, x: (day.in_time_zone.change(hour: 12).to_f - start) / span, boundary: (day.in_time_zone.to_f - start) / span } } : []
    @points = range.weights.map do |weight|
      { x: (weight.recorded_at.to_f - start) / span,
        y: (weight.in_unit(unit) - minimum) / (maximum - minimum), weight: weight }
    end
    @injections = range.injections.map { |shot| { x: (shot.recorded_at.to_f - start) / span, injection: shot } }
    occupied = []
    @injections.each do |event|
      label_x = (40 + event[:x] * 640).clamp(80, 640)
      lane = occupied.find_index { |right| label_x - 75 > right + 8 } || occupied.size
      occupied[lane] = label_x + 75
      event.merge!(label_x: label_x, lane: lane)
    end
  end

  def injection_lanes = injections.map { |event| event[:lane] + 1 }.max || 0

  # Estimated edge points plus actual readings, in time order, for shading.
  def area_points = [estimates[:start], *points, estimates[:end]].compact

  # Dashed connectors: week start to the first reading, last reading to week end
  # (or straight across when the range itself has no readings).
  def estimate_segments
    first = points.first || estimates[:end]
    last = points.last || estimates[:start]
    segments = []
    segments << [estimates[:start], first] if estimates[:start] && first
    segments << [last, estimates[:end]] if estimates[:end] && last && points.any?
    segments
  end

  # Stacks fixed-width shot labels into rows so none overlap, for a plot area
  # starting at `left` and `width` units wide.
  def label_lanes(left:, width:, half:, gap: 4)
    occupied = []
    injections.map do |event|
      x = (left + event[:x] * width).clamp(left + half, left + width - half)
      lane = occupied.find_index { |right| x - half > right + gap } || occupied.size
      occupied[lane] = x + half
      event.merge(label_x: x, lane: lane)
    end
  end

  private

  def interpolate(from, to, at, unit)
    a, b = from.in_unit(unit), to.in_unit(unit)
    t0, t1 = from.recorded_at.to_f, to.recorded_at.to_f
    return b if t1 == t0
    a + (b - a) * ((at - t0) / (t1 - t0))
  end
end
