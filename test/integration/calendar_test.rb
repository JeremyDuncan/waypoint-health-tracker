require "test_helper"

class CalendarTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @other = create_user("other@example.test")
    @user.update!(reminder_at: "2026-11-09T09:00:00-05:00")
    ["2026-10-31T23:55:00-04:00", "2026-11-01T00:05:00-04:00",
     "2026-11-15T08:00:00-05:00", "2026-11-15T20:00:00-05:00",
     "2026-11-30T23:55:00-05:00", "2026-12-01T00:05:00-05:00"].each do |timestamp|
      @user.weights.create!(value: "200", unit: "lb", occurred_at: timestamp)
    end
    @user.injections.create!(dose: "5", occurred_at: "2026-11-03T09:00:00-05:00")
    @user.day_notes.create!(local_date: "2026-11-04", notes: "Calendar note")
    @user.day_notes.create!(local_date: "2026-11-05", metrics: { "sleep_hours" => "7.5" })
    @user.day_notes.create!(local_date: "2026-11-06", notes: "")
    @other.weights.create!(value: "180", unit: "lb", occurred_at: "2026-11-03T08:00:00-05:00")
    @other.injections.create!(dose: "15", occurred_at: "2026-11-03T09:00:00-05:00")
    @other.day_notes.create!(local_date: "2026-11-01", notes: "other-private-calendar-note")
    login(@user)
  end

  test "full selected month uses local day boundaries, counts multiple events, and is independent of the chart range" do
    get calendar_path(month: "2026-11", range: "custom", from: "2026-11-01", to: "2026-11-01")
    assert_response :success
    assert_select "#calendar-heading", text: "November 2026"
    assert_select ".timeline-card", 0
    assert_select "a.calendar-day", 30
    assert_select ".calendar-totals", text: /4 weigh-ins.*1 injection.*2 journal days/m
    assert_select '[data-calendar-date="2026-11-01"] .calendar-weight', text: /1.*weigh-in/m
    assert_select '[data-calendar-date="2026-11-15"] .calendar-weight', text: /2.*weigh-ins/m
    assert_select '[data-calendar-date="2026-11-30"] .calendar-weight', text: /1.*weigh-in/m
    assert_select '[data-calendar-date="2026-11-03"] .calendar-injection', 1
    assert_select '[data-calendar-date="2026-11-03"] .calendar-weight', 0
    assert_select '[data-calendar-date="2026-11-04"] .calendar-journal', 1
    assert_select '[data-calendar-date="2026-11-05"] .calendar-journal', 1
    assert_select '[data-calendar-date="2026-11-06"] .calendar-journal', 0
    assert_select '[data-calendar-date="2026-11-09"] .calendar-injection', 0
    assert_select '[data-calendar-date="2026-11-01"] .calendar-journal', 0
    assert_select '[data-calendar-date="2026-10-31"]', 0
    assert_select '[data-calendar-date="2026-12-01"]', 0
    assert_select '[data-calendar-date="2026-11-04"][href="/journal/2026-11-04"][data-turbo-frame="_top"]', 1
    refute_includes response.body, "other-private-calendar-note"
    # Month navigation stays on the dedicated calendar page.
    assert_select '.calendar-navigation a[aria-label="Next calendar month"]' do |links|
      assert_includes links.first["href"], "month=2026-12"
      assert links.first["href"].start_with?(calendar_path)
    end
  end

  test "calendar is linked from navigation and is no longer embedded in the overview" do
    get root_path
    assert_response :success
    assert_select "#month-calendar", 0
    assert_select 'nav[aria-label="Main navigation"] a[href="/calendar"]', text: "Calendar"
    delete session_path
    get calendar_path
    assert_redirected_to new_session_path
  end

  test "another account sees only its own calendar activity" do
    login(@other)
    get calendar_path(month: "2026-11")
    assert_response :success
    assert_select ".calendar-totals", text: /1 weigh-in.*1 injection.*1 journal day/m
    assert_select '[data-calendar-date="2026-11-15"] .calendar-weight', 0
    assert_select '[data-calendar-date="2026-11-04"] .calendar-journal', 0
    refute_includes response.body, "Calendar note"
  end

  test "month navigation handles leap days and year boundaries and empty days open journals" do
    get calendar_path(month: "2024-02")
    assert_response :success
    assert_select "a.calendar-day", 29
    assert_select '[data-calendar-date="2024-02-29"][href="/journal/2024-02-29"]', 1
    assert_select ".calendar-empty", text: /No entries this month/
    get calendar_path(month: "2026-12")
    assert_select '.calendar-navigation a[aria-label="Next calendar month"]' do |links|
      assert_includes links.first["href"], "month=2027-01"
    end
    assert_no_difference("DayNote.count") { get journal_path("2024-02-29") }
    assert_response :success
    assert_select "a.back-link" do |links|
      assert_equal calendar_path(month: "2024-02", anchor: "month-calendar"), links.first["href"]
    end
  end

  test "invalid month returns an actionable error and a usable calendar" do
    get calendar_path(month: "2026-13")
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /Choose a calendar month/
    assert_select "#month-calendar", 1
  end
end
