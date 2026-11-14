# Monotone cubic segments preserve every recorded point without overshooting
# between neighbors. Repeated timestamps remain vertical segments.
class SmoothLine
  def self.segments(points)
    return [] if points.size < 2
    slopes = points.each_cons(2).map { |a, b| b[:x] == a[:x] ? 0.0 : (b[:y] - a[:y]) / (b[:x] - a[:x]) }
    tangents = points.each_index.map do |index|
      if index.zero? then slopes.first
      elsif index == points.size - 1 then slopes.last
      elsif slopes[index - 1] * slopes[index] <= 0 then 0.0
      else (slopes[index - 1] + slopes[index]) / 2
      end
    end
    slopes.each_with_index do |slope, index|
      if slope.zero?
        tangents[index] = tangents[index + 1] = 0.0
      else
        a, b = tangents[index] / slope, tangents[index + 1] / slope
        if a * a + b * b > 9
          factor = 3 / Math.sqrt(a * a + b * b)
          tangents[index] = factor * a * slope
          tangents[index + 1] = factor * b * slope
        end
      end
    end
    points.each_cons(2).with_index.map do |(a, b), index|
      width = (b[:x] - a[:x]) / 3
      { from: a, to: b, controls: [{ x: a[:x] + width, y: a[:y] + tangents[index] * width }, { x: b[:x] - width, y: b[:y] - tangents[index + 1] * width }] }
    end
  end
end
