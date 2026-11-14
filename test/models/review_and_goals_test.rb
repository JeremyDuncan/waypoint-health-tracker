require "test_helper"

class ReviewAndGoalsTest < ActiveSupport::TestCase
  setup { @user = create_user }

  test "goal metrics use actual current weight, explicit height, converted changes and remaining distance" do
    @user.update!(height_cm: "180", weight_goal: { mode: "target", value: "180", unit: "lb", start_date: "2026-01-01", low: nil, high: nil })
    @user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-01-01T08:00:00-05:00")
    current = @user.weights.create!(value: 90, unit: "kg", occurred_at: "2026-01-02T08:00:00-05:00")
    @user.weights.create!(value: 170, unit: "lb", occurred_at: "2026-01-30T08:00:00-05:00")
    report = GoalProgress.new(@user, now: Time.iso8601("2026-01-25T12:00:00Z"))
    assert_equal current.id, report.current.id
    assert_in_delta 90 / 1.8**2, report.bmi, 1e-8
    assert_in_delta 90 / 0.45359237 - 200, report.change, 1e-8
    assert_in_delta 90 / 0.45359237 - 180, report.remaining, 1e-8
    @user.update!(height_cm: nil)
    assert_nil GoalProgress.new(@user).bmi
  end

  test "weekly review uses local Monday boundaries, individual readings, actual shots and independently logged metrics" do
    @user.weights.create!(value: 210, unit: "lb", occurred_at: "2026-11-02T08:00:00-05:00")
    @user.weights.create!(value: 208, unit: "lb", occurred_at: "2026-11-08T23:55:00-05:00")
    @user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-09T00:05:00-05:00")
    @user.weights.create!(value: 198, unit: "lb", occurred_at: "2026-11-09T08:00:00-05:00")
    @user.weights.create!(value: 196, unit: "lb", occurred_at: "2026-11-12T08:00:00-05:00")
    @user.injections.create!(dose: 5, occurred_at: "2026-11-10T09:00:00-05:00")
    @user.day_notes.create!(local_date: "2026-11-11", notes: "A note", metrics: { "severity" => 0, "appetite" => 4 })
    @user.day_notes.create!(local_date: "2026-11-13", metrics: { "appetite" => 6 })
    @user.update!(reminder_at: "2026-11-14T09:00:00-05:00")
    other = create_user("other@example.test")
    other.weights.create!(value: 300, unit: "lb", occurred_at: "2026-11-10T08:00:00-05:00")
    Time.use_zone(@user.time_zone) do
      travel_to Time.iso8601("2026-11-14T12:00:00-05:00") do
        review = WeeklyReview.new(@user)
        assert_equal Date.new(2026, 11, 9), review.from
        assert_equal Date.new(2026, 11, 14), review.through
        assert review.partial?
        assert_in_delta 198, review.average
        assert_in_delta 209, review.previous_average
        assert_in_delta(-11, review.change)
        assert_in_delta(-11.0 / 209 * 100, review.average_change_percent, 1e-8)
        assert_in_delta(-2, review.within_week_percent, 1e-8)
        assert_equal 2, review.weighed_days
        assert_equal 2, review.journal_days
        assert_equal 1, review.current.injections.size
        assert_equal 5, review.metric_summaries.find { |metric| metric[:key] == "appetite" }[:average]
        assert_equal 0, review.metric_summaries.find { |metric| metric[:key] == "severity" }[:average]
        assert_raises(ArgumentError) { WeeklyReview.new(@user, "2026-11-16") }
        assert_raises(Date::Error) { WeeklyReview.new(@user, "invalid") }
        empty = WeeklyReview.new(@user, "2026-10-05")
        assert_nil empty.average
        assert_nil empty.change
        assert_nil empty.average_change_percent
        assert_nil empty.within_week_percent
      end
    end
  end

  test "weekly chart estimates its edges from the nearest readings outside the week, never past today, across any gap" do
    weigh = ->(value, at) { @user.weights.create!(value: value, unit: "lb", occurred_at: at) }
    weigh.(220, "2026-03-02T08:00:00-05:00")   # months before anything else
    weigh.(202, "2026-11-01T12:00:00-05:00")   # Sunday before the week of Nov 2
    weigh.(200, "2026-11-03T00:00:00-05:00")
    weigh.(198, "2026-11-05T00:00:00-05:00")
    weigh.(196, "2026-11-10T00:00:00-05:00")   # Tuesday after it
    weigh.(194, "2026-11-24T00:00:00-05:00")
    Time.use_zone(@user.time_zone) do
      travel_to Time.iso8601("2026-12-01T12:00:00-05:00") do
        plot = WeeklyReview.new(@user, "2026-11-02").plot
        # Monday 00:00 is 12 of the 36 hours between Sunday noon and Tuesday.
        assert_in_delta 202 - 2.0 * 12 / 36, plot.estimates[:start][:value], 1e-8
        # Next Monday 00:00 is 4 of the 5 days between Thursday and Tuesday.
        assert_in_delta 198 - 2.0 * 4 / 5, plot.estimates[:end][:value], 1e-8
        assert_equal [0.0, 1.0], plot.area_points.values_at(0, -1).map { |point| point[:x] }
        assert_equal 2, plot.estimate_segments.length
        assert_equal 2, plot.points.length, "estimates are never added as readings"

        # A week with no readings is bridged by one straight estimate.
        empty = WeeklyReview.new(@user, "2026-11-16").plot
        assert_empty empty.points
        assert_in_delta 196 - 2.0 * 6 / 14, empty.estimates[:start][:value], 1e-8
        assert_in_delta 196 - 2.0 * 13 / 14, empty.estimates[:end][:value], 1e-8
        assert_equal 1, empty.estimate_segments.length

        # Weeks inside a months-long gap are bridged from the readings on either side.
        gap = WeeklyReview.new(@user, "2026-10-05").plot
        assert_equal %i[start end], gap.estimates.keys
        assert_equal 1, gap.estimate_segments.length
        assert gap.estimates[:start][:value].between?(202, 220)
        assert_operator gap.estimates[:end][:value], :<, gap.estimates[:start][:value]
        # Before the first reading ever there is nothing to estimate from.
        assert_empty WeeklyReview.new(@user, "2026-02-02").plot.estimates
      end
      # In the current week nothing comes after today, so the line ends at the last reading.
      travel_to Time.iso8601("2026-11-05T12:00:00-05:00") do
        current = WeeklyReview.new(@user).plot
        assert current.estimates.key?(:start)
        assert_not current.estimates.key?(:end)
        assert_equal 1, current.estimate_segments.length
      end
    end
  end

  test "goal progress retains first observed milestones through regain and ignores future measurements" do
    @user.update!(weight_goal: { mode: "target", value: "180.0", unit: "lb", start_date: "2026-01-01", low: nil, high: nil })
    [["2025-12-31", 220], ["2026-01-01", 200], ["2026-01-08", 190], ["2026-01-15", 185], ["2026-01-20", 195], ["2026-01-30", 160]].each do |day, value|
      @user.weights.create!(value: value, unit: "lb", occurred_at: "#{day}T08:00:00-05:00")
    end
    data = GoalProgress.new(@user, now: Time.iso8601("2026-01-25T12:00:00Z"))
    assert_equal 4, data.weights.size
    assert_in_delta 25, data.percent
    assert_equal [195, 190, 185, 180], data.milestones.map { |milestone| milestone[:value] }
    assert_equal [Date.new(2026, 1, 8), Date.new(2026, 1, 8), Date.new(2026, 1, 15), nil], data.milestones.map { |milestone| milestone[:reached]&.local_day }
    assert_equal 195, data.latest.value
    @user.update!(preferred_unit: "kg")
    assert_in_delta 25, GoalProgress.new(@user, now: Time.iso8601("2026-01-25T12:00:00Z")).percent
  end

  test "maintenance counts last measured reading per local day and goals export and import without duplicates" do
    @user.update!(height_cm: "177.8", weight_goal: { mode: "maintenance", value: nil, unit: "lb", start_date: "2026-01-01", low: "190", high: "200" })
    [["2026-01-01T08:00:00-05:00", 205], ["2026-01-01T18:00:00-05:00", 195], ["2026-01-02T08:00:00-05:00", 189], ["2026-01-03T08:00:00-05:00", 198]].each do |time, value|
      @user.weights.create!(value: value, unit: "lb", occurred_at: time)
    end
    progress = GoalProgress.new(@user, now: Time.iso8601("2026-01-25T12:00:00Z"))
    assert progress.maintenance?
    assert_equal 2, progress.days_in_range
    assert_equal 3, progress.measured_days
    target = create_user("target@example.test")
    payload = PersonalImport.parse_json(PersonalExport.new(@user).document.to_json)
    importer = PersonalImport.new(target, payload)
    assert_empty importer.report["errors"]
    importer.commit!(target.import_batches.create!(payload: payload), apply_preferences: true)
    assert_equal @user.weight_goal, target.reload.weight_goal
    assert_equal @user.height_cm, target.height_cm
    assert_equal 4, importer.report["duplicates"]
    assert_no_difference("Weight.count") { importer.commit!(target.import_batches.create!(payload: payload), apply_preferences: true) }
    legacy = PersonalExport.new(@user).document
    legacy["preferences"].delete("weight_goal")
    legacy["preferences"].delete("height_cm")
    assert_empty PersonalImport.new(target, PersonalImport.parse_json(legacy.to_json)).report["errors"]
    @user.weight_goal["high"] = "180"
    assert_not @user.valid?
  end
end
