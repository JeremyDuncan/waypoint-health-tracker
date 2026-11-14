require "test_helper"

class TimelineTest < ActiveSupport::TestCase
  test "daily chart context uses actual local midnights and noon across a daylight-saving change" do
    user = create_user
    Time.use_zone(user.time_zone) do
      days = Timeline.new(user, range: "custom", from: "2026-10-31", to: "2026-11-02").chart[:days]
      assert_equal ["2026-10-31", "2026-11-01", "2026-11-02"], days.map { |day| day[:day] }
      assert_equal [24, 25, 24], days.map { |day| (day[:finish] - day[:start]) / 3_600_000 }
      assert days.all? { |day| Time.at(day[:noon] / 1000).in_time_zone.hour == 12 }
    end
  end
  test "rolling trend uses a trailing 168-hour window with earlier context and no fabricated daily readings" do
    user = create_user
    user.weights.create!(value: 300, unit: "lb", occurred_at: "2026-10-25T08:00:00-04:00")
    user.weights.create!(value: 202, unit: "lb", occurred_at: "2026-11-01T08:00:00-05:00")
    user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-02T08:00:00-05:00")
    user.weights.create!(value: 90, unit: "kg", occurred_at: "2026-11-08T08:00:00-05:00")
    other = create_user("other@example.test")
    other.weights.create!(value: 300, unit: "lb", occurred_at: "2026-11-02T08:00:00-05:00")
    Time.use_zone(user.time_zone) do
      chart = Timeline.new(user, range: "custom", from: "2026-11-02", to: "2026-11-08").chart
      assert_equal 2, chart[:trend].size
      assert_equal chart[:raw].map { |point| point[:x] }, chart[:trend].map { |point| point[:x] }
      assert_in_delta 201, chart[:trend].first[:y]
      assert_in_delta((200 + 90 / 0.45359237) / 2, chart[:trend].last[:y], 0.000001)
      assert_equal [2, 2], chart[:trend].map { |point| point[:count] }
    end
  end
  test "monthly means use all individual selected readings in local calendar months and retain actual last timestamps" do
    user = create_user
    user.weights.create!(value: 500, unit: "lb", occurred_at: "2023-12-31T23:55:00-05:00")
    user.weights.create!(value: 200, unit: "lb", occurred_at: "2024-01-01T08:00:00-05:00")
    user.weights.create!(value: 202, unit: "lb", occurred_at: "2024-01-31T08:00:00-05:00")
    january_last = user.weights.create!(value: 90, unit: "kg", occurred_at: "2024-01-31T23:55:00-05:00")
    february_first = user.weights.create!(value: 198, unit: "lb", occurred_at: "2024-02-01T00:05:00-05:00")
    february_last = user.weights.create!(value: 196, unit: "lb", occurred_at: "2024-02-29T08:00:00-05:00")
    april_last = user.weights.create!(value: 194, unit: "lb", occurred_at: "2024-04-01T08:00:00-04:00")
    user.weights.create!(value: 500, unit: "lb", occurred_at: "2024-05-01T00:05:00-04:00")
    other = create_user("other@example.test")
    other.weights.create!(value: 300, unit: "lb", occurred_at: "2024-02-15T08:00:00-05:00")
    user.injections.create!(dose: 5, occurred_at: "2024-03-15T09:00:00-04:00")
    user.day_notes.create!(local_date: "2024-03-16", notes: "No weight this month")
    Time.use_zone(user.time_zone) do
      range = Timeline.new(user, range: "custom", from: "2024-01-01", to: "2024-04-30")
      chart = range.chart
      assert_equal [3, 2, 1], chart[:monthly].map { |point| point[:count] }
      assert_equal ["2024-01-31", "2024-02-29", "2024-04-01"], chart[:monthly].map { |point| point[:day] }
      assert_equal [january_last, february_last, april_last].map { |weight| weight.recorded_at.to_f * 1000 }, chart[:monthly].map { |point| point[:x] }
      assert_in_delta((200 + 202 + 90 / 0.45359237) / 3, chart[:monthly].first[:y], 0.000001)
      assert_in_delta 197, chart[:monthly][1][:y], 0.000001
      assert_equal 6, chart[:raw].length
      assert_equal "2024-03-15", chart[:injections].first[:day]
      assert_not chart[:injections].first.key?(:y)
      assert_equal "2024-03-16", chart[:notes].first[:day]
      partial = Timeline.new(user, range: "custom", from: "2024-02-01", to: "2024-02-15").chart[:monthly]
      assert_equal 1, partial.first[:count]
      assert_equal february_first.recorded_at.to_f * 1000, partial.first[:x]
      assert_in_delta 198, partial.first[:y], 0.000001
      user.update!(preferred_unit: "kg")
      assert_in_delta 197 * 0.45359237, range.chart[:monthly][1][:y], 0.000001
    end
  end

  test "empty months never receive fabricated averages" do
    user = create_user
    Time.use_zone(user.time_zone) do
      assert_empty Timeline.new(user, range: "all").chart[:monthly]
    end
  end
end
