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
    assert_select '[data-calendar-date="2026-11-04"][href="/calendar/2026-11-04"][data-turbo-frame="calendar-day"]', 1
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

  test "month navigation handles leap days and year boundaries and empty days can be opened" do
    get calendar_path(month: "2024-02")
    assert_response :success
    assert_select "a.calendar-day", 29
    assert_select '[data-calendar-date="2024-02-29"][href="/calendar/2024-02-29"]', 1
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

  test "a calendar day shows its own entries and offers forms for that date" do
    get calendar_day_path("2026-11-03"), headers: { "Turbo-Frame" => "calendar-day" }
    assert_response :success
    assert_select "turbo-frame#calendar-day" do
      assert_select ".day-list li", 1
      assert_select ".day-list .dose-dot.dose-5", 1
      assert_select "a[href=?]", new_entry_path(kind: "weight", date: "2026-11-03")
      assert_select "a[href=?]", new_entry_path(kind: "injection", date: "2026-11-03")
      assert_select "form[action=?] input[name=return_to][value=calendar]", journal_path("2026-11-03")
    end
    get new_entry_path(kind: "weight", date: "2026-11-03")
    assert_select "input[type=datetime-local][value=?]", "2026-11-03T12:00"
    assert_select "input[type=hidden][name=date][value=?]", "2026-11-03"
    get new_entry_path(kind: "weight", date: "not-a-date")
    assert_response :success
    assert_select "input[type=hidden][name=date]", 0
    delete session_path
    get calendar_day_path("2026-11-03")
    assert_redirected_to new_session_path
  end

  test "entries and journals added from the calendar return to their month" do
    { "weight" => { value: "199", unit: "lb" }, "injection" => { dose: "7.5" } }.each do |kind, attrs|
      params = { date: "2026-11-20", entry: { id: SecureRandom.uuid, local_time: "2026-11-20T12:00", **attrs } }
      2.times do
        post entries_path(kind: kind), params: params, as: :json
        assert_equal calendar_path(month: "2026-11"), response.parsed_body["redirect_to"]
      end
    end
    put journal_path("2026-11-20"), params: { return_to: "calendar", day_note: { notes: "From calendar" } }
    assert_redirected_to calendar_path(month: "2026-11")
    get calendar_path(month: "2026-11")
    assert_select '[data-calendar-date="2026-11-20"]' do
      assert_select ".calendar-weight", text: /1/
      assert_select ".calendar-injection.dose-7-5", text: /7.5 mg/
      assert_select ".calendar-journal", 1
    end
    post entries_path(kind: "weight"), params: { entry: { id: SecureRandom.uuid, local_time: "2026-11-21T12:00", value: "198", unit: "lb" } }, as: :json
    assert_equal root_path, response.parsed_body["redirect_to"]
  end

  test "every dose has its own color in both themes" do
    css = Rails.root.join("app/assets/stylesheets/application.css").read
    helper = ApplicationController.helpers
    names = InjectionInsights::DOSES.map { |dose| helper.dose_class(dose) }
    assert_equal %w[dose-2-5 dose-5 dose-7-5 dose-10 dose-12-5 dose-15], names
    palettes = names.map { |name| css.scan(/--#{name}:(#\h{6})/).flatten }
    assert_equal [3], palettes.map(&:size).uniq
    palettes.transpose.each { |theme| assert_equal theme.uniq, theme }
  end
end
