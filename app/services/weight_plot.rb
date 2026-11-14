class WeightPlot
  attr_reader :points, :injections, :minimum, :maximum, :days
  def initialize(range, unit, display_to: range.to)
    values = range.weights.map { |weight| weight.in_unit(unit) }
    @minimum = values.min || 0
    @maximum = values.max || 1
    padding = [(@maximum - @minimum) * 0.12, 0.5].max
    @minimum -= padding
    @maximum += padding
    start = range.from.in_time_zone.to_f
    span = (display_to + 1).in_time_zone.to_f - start
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
end
