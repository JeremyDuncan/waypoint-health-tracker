require "test_helper"

class InjectionInsightsTest < ActiveSupport::TestCase
  setup { @user = create_user }

  def shot(time, dose: 5, site: "Abdomen", side: "Left")
    @user.injections.create!(occurred_at: time, dose: dose, site: site, side: side)
  end

  def weigh(time, value, unit: "lb")
    @user.weights.create!(occurred_at: time, value: value, unit: unit)
  end

  def report(options = {}, now: Time.iso8601("2026-01-25T12:00:00Z"), **filters)
    InjectionInsights.new(@user, { range: "custom", from: "2026-01-01", to: "2026-01-31" }.merge(options).merge(filters), now: now)
  end

  test "uses actual reading endpoints and the next global shot even when filters hide it" do
    first = shot("2026-01-01T09:00:00-05:00", dose: 2.5)
    second = shot("2026-01-04T09:00:00-05:00", site: "Thigh", side: "Right")
    third = shot("2026-01-11T09:00:00-05:00", dose: 7.5, side: "Right")
    baseline = weigh("2026-01-01T08:00:00-05:00", 200)
    weigh("2026-01-02T08:00:00-05:00", 199)
    boundary_weight = weigh("2026-01-04T09:00:00-05:00", 198)
    weigh("2026-01-06T08:00:00-05:00", 197)
    weigh("2026-01-11T09:00:00-05:00", 196)
    weigh("2026-01-15T08:00:00-05:00", 194)
    data = report(site: "Abdomen")
    assert_equal [first.id, third.id], data.rows.map { |row| row[:injection].id }
    assert_equal second.id, data.rows.first[:following].id
    assert_equal second.recorded_at, data.rows.first[:boundary]
    assert_equal baseline.id, data.rows.first[:baseline].id
    assert_equal boundary_weight.id, data.rows.first[:followup].id
    assert_in_delta(-2, data.rows.first[:change], 0.000001)
    assert_equal 2, data.compared_rows.length
    assert_in_delta(-2, data.mean_change, 0.000001)
    assert_in_delta(-6, data.overall_change, 0.000001)
    assert_in_delta(-3, data.overall_percent, 0.000001)
    assert_in_delta((-2.0 / 200 * 100 - 2.0 / 196 * 100) / 2, data.mean_percent, 0.000001)
    assert_in_delta(-1, data.chart[:shots].first[:percent], 0.000001)
    assert_equal 1, data.locations["Abdomen"][:sides]["Left"]
    assert_equal 1, data.locations["Abdomen"][:sides]["Right"]
    assert_equal ["2.5 mg", "7.5 mg"], data.dose_groups.map { |group| group[:label] }
    # Group percentages compare the group's total with its first baseline reading.
    assert_in_delta(-1, data.dose_groups.first[:percent], 0.000001)
    assert_in_delta(-2.0 / 196 * 100, data.dose_groups.last[:percent], 0.000001)
    assert_in_delta(-1, data.site_groups.find { |group| group[:label] == "Abdomen · Left" }[:percent], 0.000001)
    # Date filters choose shots; later measured follow-ups remain available.
    one_day = report(from: "2026-01-01", to: "2026-01-01")
    assert_equal 1, one_day.rows.length
    assert_equal boundary_weight.id, one_day.rows.first[:followup].id
    assert_equal 3, one_day.chart[:trajectories].first[:points].length
    assert_in_delta(-1.0 / 24, one_day.chart[:trajectories].first[:points].first[:x], 0.000001)
  end

  test "stale or missing baselines and missing followups stay missing rather than becoming zero change" do
    shot("2026-01-06T09:00:00-05:00")
    weigh("2026-01-02T09:00:00-05:00", 210)
    weigh("2026-01-07T09:00:00-05:00", 208)
    data = report
    assert_equal :no_baseline, data.rows.first[:status]
    assert_nil data.rows.first[:change]
    assert_nil data.mean_change
    assert_nil data.overall_percent
    assert_nil data.mean_percent
    assert_nil data.chart[:shots].first[:change]
    assert_empty data.chart[:trajectories]
    @user.weights.delete_all
    weigh("2026-01-06T08:00:00-05:00", 210)
    data = report
    assert_equal :no_followup, data.rows.first[:status]
    assert_nil data.rows.first[:change]
    assert_nil data.site_groups.first[:change]
    assert_nil data.site_groups.first[:percent]
  end

  test "ongoing windows show measured changes but stay out of completed comparisons and ignore future readings" do
    shot("2026-01-20T09:00:00-05:00")
    weigh("2026-01-20T08:00:00-05:00", 200)
    weigh("2026-01-21T08:00:00-05:00", 199)
    weigh("2026-01-24T08:00:00-05:00", 195)
    data = report(now: Time.iso8601("2026-01-22T12:00:00-05:00"))
    assert_equal :open, data.rows.first[:status]
    assert_in_delta(-1, data.rows.first[:change], 0.000001)
    assert_empty data.compared_rows
    assert_nil data.mean_change
    assert_equal 1, data.open_count
    assert_equal 1, data.rows.first[:readings].length
    assert_equal 1, data.chart[:trajectories].length
    # Dose and location totals include the in-progress window, marked as such.
    group = data.dose_groups.sole
    assert_in_delta(-1, group[:change], 0.000001)
    assert_equal 1, group[:measured]
    assert_equal 1, group[:in_progress]
  end

  test "dose and location groups add up every measured shot, including one in progress" do
    shot("2026-01-01T09:00:00-05:00", dose: 2.5, site: "Thigh", side: "Right")
    shot("2026-01-08T09:00:00-05:00", dose: 2.5, site: "Thigh", side: "Left")
    shot("2026-01-15T09:00:00-05:00", dose: 2.5, site: "Abdomen", side: "Right")
    weigh("2026-01-01T08:00:00-05:00", 210)
    weigh("2026-01-08T08:00:00-05:00", 205.4)
    weigh("2026-01-15T08:00:00-05:00", 203)
    weigh("2026-01-18T08:00:00-05:00", 200.2)
    data = report(now: Time.iso8601("2026-01-19T12:00:00-05:00"))
    assert_equal %i[complete complete open], data.rows.map { |row| row[:status] }
    group = data.dose_groups.sole
    assert_equal "2.5 mg", group[:label]
    assert_in_delta(-9.8, group[:change], 0.000001)
    assert_in_delta(-9.8 / 210 * 100, group[:percent], 0.000001)
    assert_in_delta(-9.8 / 3, group[:average], 0.000001)
    assert_equal [3, 3, 1], group.values_at(:shots, :measured, :in_progress)
    # Location groups total the same way and together add up to the dose total.
    assert_in_delta(group[:change], data.site_groups.sum { |site| site[:change] }, 0.000001)
  end

  test "completed but very short measurement spans are labeled and excluded from site averages" do
    shot("2026-01-01T09:00:00-05:00")
    weigh("2026-01-01T08:00:00-05:00", 200)
    weigh("2026-01-01T10:00:00-05:00", 199)
    data = report
    assert_equal :short, data.rows.first[:status]
    assert_in_delta(-1, data.rows.first[:change], 0.000001)
    assert_equal 0, data.site_groups.first[:measured]
    assert_nil data.site_groups.first[:change]
  end

  test "a long gap before the next shot never extends the seven-day window" do
    first = shot("2026-01-01T09:00:00-05:00")
    following = shot("2026-01-15T09:00:00-05:00")
    weigh("2026-01-01T08:00:00-05:00", 200)
    endpoint = weigh("2026-01-08T09:00:00-05:00", 198)
    late = weigh("2026-01-09T08:00:00-05:00", 190)
    weigh("2026-01-15T08:00:00-05:00", 189)
    weigh("2026-01-16T08:00:00-05:00", 188)
    data = report
    row = data.rows.find { |entry| entry[:injection].id == first.id }
    assert_equal following.id, row[:following].id
    assert_equal Time.iso8601("2026-01-08T09:00:00-05:00"), row[:boundary]
    assert_equal endpoint.id, row[:followup].id
    assert_not row[:ended_by_next]
    assert_in_delta(-2, row[:change], 0.000001)
    points = data.chart[:trajectories].find { |entry| entry[:id] == first.id }[:points]
    assert_not_includes points.map { |point| point[:at] }, late.recorded_at.iso8601
  end

  test "future-dated logs have no measurements or comparison values" do
    future = shot("2026-01-26T09:00:00-05:00")
    weigh("2026-01-25T08:00:00-05:00", 200)
    weigh("2026-01-26T08:00:00-05:00", 199)
    weigh("2026-01-27T08:00:00-05:00", 198)
    data = report
    assert_equal future.id, data.rows.first[:injection].id
    assert_equal :future, data.rows.first[:status]
    assert_nil data.rows.first[:baseline]
    assert_nil data.rows.first[:followup]
    assert_nil data.rows.first[:change]
    assert_nil data.mean_change
    assert_empty data.chart[:trajectories]
    assert_empty data.compared_rows
  end

  test "multiple daily readings and mixed units preserve exact endpoints with converted changes" do
    shot("2026-01-01T09:00:00-05:00", site: nil, side: nil)
    weigh("2026-01-01T06:00:00-05:00", 201)
    baseline = weigh("2026-01-01T08:00:00-05:00", 200)
    weigh("2026-01-02T07:00:00-05:00", 199)
    followup = weigh("2026-01-02T08:00:00-05:00", "90", unit: "kg")
    data = report
    assert_equal baseline.id, data.rows.first[:baseline].id
    assert_equal followup.id, data.rows.first[:followup].id
    assert_equal 2, data.rows.first[:readings].length
    assert_in_delta(90 / 0.45359237 - 200, data.rows.first[:change], 0.000001)
    assert_equal 1, data.locations["Not recorded"][:count]
    assert_equal "Not recorded · Not recorded", data.site_groups.first[:label]
    @user.update!(preferred_unit: "kg")
    assert_in_delta(90 - 200 * 0.45359237, report.rows.first[:change], 0.000001)
  end

  test "local midnight filters and daylight-saving boundaries use the personal time zone" do
    shot("2026-01-31T23:55:00-05:00")
    data = report(from: "2026-01-31", to: "2026-01-31", now: Time.iso8601("2026-02-10T12:00:00Z"))
    assert_equal 1, data.rows.length
    assert_empty data.chart[:history][:raw]
    assert_equal Time.iso8601("2026-01-31T00:00:00-05:00").to_f * 1000, data.chart[:history][:from]
    assert_not data.chart[:history][:injections].first.key?(:y)
    assert_equal "2026-01-31", data.chart[:shots].first[:day]
    @user.injections.delete_all
    shot("2026-10-28T09:00:00-04:00")
    data = report(from: "2026-10-28", to: "2026-10-28", now: Time.iso8601("2026-11-15T12:00:00Z"))
    assert_equal "2026-11-04T09:00:00-05:00", data.rows.first[:boundary].in_time_zone(@user.time_zone).iso8601
  end

  test "another account's readings and shots never affect a window or create a baseline" do
    own = shot("2026-01-01T09:00:00-05:00")
    other = create_user("other@example.test")
    other.weights.create!(occurred_at: "2026-01-01T08:00:00-05:00", value: 200, unit: "lb")
    other.weights.create!(occurred_at: "2026-01-02T08:00:00-05:00", value: 198, unit: "lb")
    other.injections.create!(occurred_at: "2026-01-02T09:00:00-05:00", dose: 15)
    data = report
    assert_equal [own.id], data.rows.map { |row| row[:injection].id }
    assert_nil data.rows.first[:baseline]
    assert_nil data.rows.first[:following]
    assert_empty data.chart[:trajectories]
    assert_equal 1, data.rows.length
    assert_empty data.chart[:history][:raw]
    assert_equal [own.id], data.chart[:history][:injections].map { |event| event[:id] }
  end

  test "reminders never become shots and invalid filters fail clearly" do
    @user.update!(reminder_at: "2026-01-01T09:00:00-05:00")
    assert_empty report.rows
    assert_raises(ArgumentError) { report(site: "Unknown site") }
    assert_raises(ArgumentError) { report(dose: "100") }
    assert_raises(ArgumentError) { report(side: "Other") }
    assert_raises(ArgumentError) { report(grouping: "best") }
  end
end
