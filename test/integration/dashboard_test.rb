require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    login(@user)
  end

  test "progress follows selected dates using first and last actual readings in the range" do
    @user.weights.create!(value: "195.2", unit: "lb", occurred_at: "2021-09-07T08:00:00-04:00")
    @user.weights.create!(value: 210, unit: "lb", occurred_at: "2026-11-01T08:00:00-05:00")
    @user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-08T00:05:00-05:00")
    @user.weights.create!(value: 199, unit: "lb", occurred_at: "2026-11-10T08:00:00-05:00")
    @user.weights.create!(value: 198, unit: "lb", occurred_at: "2026-11-14T23:55:00-05:00")
    @user.weights.create!(value: 190, unit: "lb", occurred_at: "2026-11-15T00:05:00-05:00")
    other = create_user("other@example.test")
    other.weights.create!(value: 300, unit: "lb", occurred_at: "2026-11-08T00:00:00-05:00")
    travel_to Time.iso8601("2026-11-14T12:00:00-05:00") do
      { "7" => "-2.0", "30" => "-12.0", "all" => "2.8" }.each do |range, expected|
        get root_path(range: range)
        assert_response :success
        assert_select 'article[aria-label="Weight change in selected range"] .stat', text: /#{Regexp.escape(expected)}/
      end
      get root_path(range: "7")
      assert_select 'article[aria-label="Weight change in selected range"] .range-percent', text: "1.0% lost"
      assert_select 'article[aria-label="Weight change in selected range"]', text: /From Nov 8, 2026 · 200.0 lb.*Through Nov 14, 2026/m
      get root_path(range: "custom", from: "2026-11-10", to: "2026-11-14")
      assert_select 'article[aria-label="Weight change in selected range"] .range-percent', text: "0.5% lost"
      assert_select 'article[aria-label="Weight change in selected range"] .stat', text: /-1.0/
      assert_select 'select[data-timeline-target="mode"] option[value="monthly"]', text: "Monthly averages"
    end
  end

  test "progress requires two readings and converts multiple same-day readings into the preferred unit" do
    travel_to Time.iso8601("2026-11-14T12:00:00-05:00") do
      get root_path(range: "7")
      assert_select 'article[aria-label="Weight change in selected range"]', text: /No weigh-ins in this range/
      @user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-14T07:00:00-05:00")
      get root_path(range: "7")
      assert_select 'article[aria-label="Weight change in selected range"] .stat', text: /—/
      assert_select 'article[aria-label="Weight change in selected range"]', text: /Log another weigh-in/
      @user.weights.create!(value: 90, unit: "kg", occurred_at: "2026-11-14T08:00:00-05:00")
      @user.update!(preferred_unit: "kg")
      get root_path(range: "7")
      assert_select 'article[aria-label="Weight change in selected range"] .stat', text: /-0.7\s*kg/
    end
  end
end
