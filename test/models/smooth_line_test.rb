require "test_helper"

class SmoothLineTest < ActiveSupport::TestCase
  test "smooth segments preserve points and stay within each pair of observed values" do
    points = [{ x: 0.0, y: 0.0 }, { x: 0.2, y: 3.0 }, { x: 0.7, y: 2.0 }, { x: 1.0, y: 4.0 }]
    segments = SmoothLine.segments(points)
    assert_equal points.each_cons(2).to_a, segments.map { |segment| [segment[:from], segment[:to]] }
    segments.each do |segment|
      a, b = segment[:from], segment[:to]
      c, d = segment[:controls]
      (0..10).each do |step|
        t = step / 10.0
        y = (1 - t)**3 * a[:y] + 3 * (1 - t)**2 * t * c[:y] + 3 * (1 - t) * t**2 * d[:y] + t**3 * b[:y]
        assert_operator y, :>=, [a[:y], b[:y]].min - 1e-8
        assert_operator y, :<=, [a[:y], b[:y]].max + 1e-8
      end
    end
  end

  test "repeated timestamps and isolated readings never generate non-finite controls or extra points" do
    points = [{ x: 0.0, y: 1.0 }, { x: 0.0, y: 2.0 }, { x: 1.0, y: 1.5 }]
    segments = SmoothLine.segments(points)
    assert_equal 2, segments.size
    assert segments.flat_map { |segment| segment[:controls] }.all? { |point| point.values.all?(&:finite?) }
    assert segments.first[:controls].all? { |point| point[:x].zero? }
    assert_empty SmoothLine.segments([])
    assert_empty SmoothLine.segments(points.first(1))
  end
end
