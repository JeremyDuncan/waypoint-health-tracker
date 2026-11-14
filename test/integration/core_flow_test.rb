require "test_helper"
class CoreFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    login(@user)
  end
  test "multiple readings, local midnight, injection-only day, independent note and filters" do
    uuid = SecureRandom.uuid
    params = { kind: "weight", entry: { id: uuid, value: "208.4000", unit: "lb", local_time: "2026-11-01T23:55" } }
    assert_difference("@user.weights.count", 1) { post entries_path, params: params }
    assert_no_difference("Weight.count") { post entries_path, params: params }
    post entries_path, params: { kind: "weight", entry: { id: SecureRandom.uuid, value: "94.3", unit: "kg", local_time: "2026-11-02T00:05" } }
    post entries_path, params: { kind: "weight", entry: { id: SecureRandom.uuid, value: "207.8", unit: "lb", local_time: "2026-11-02T08:20" } }
    assert_equal "lb", @user.reload.preferred_unit
    post entries_path, params: { kind: "injection", entry: { id: SecureRandom.uuid, dose: "5", site: "Thigh", side: "Left", notes: "Actual dose", local_time: "2026-11-03T09:30" } }
    assert_response :see_other
    put journal_path("2026-11-04"), params: { day_note: { notes: "A good day 🌿", metrics: { sleep_hours: "7.5", appetite: "4" } } }
    assert_response :see_other
    Time.use_zone(@user.time_zone) do
      range = Timeline.new(@user, range: "custom", from: "2026-11-02", to: "2026-11-04")
      assert_equal 2, range.weights.size
      assert_equal 1, range.injections.size
      assert_equal 1, range.notes.size
      chart = range.chart
      assert_equal ["2026-11-02"] * 2, chart[:raw].map { |x| x[:day] }
      assert_equal "2026-11-03", chart[:injections][0][:day]
      refute chart[:injections][0].key?(:y), "Injection must not have a fabricated weight"
      assert_equal 2, chart[:weekly][0][:count]
      boundary = Timeline.new(@user, range: "custom", from: "2026-11-01", to: "2026-11-01")
      assert_equal 1, boundary.weights.size
    end
    %w[7 30 90 365 all].each do |preset|
      get root_path(range: preset)
      assert_response :success
    end
    get root_path(range: "custom", from: "2026-11-02", to: "2026-11-04")
    assert_select ".range-table tbody tr", 4
    assert_select "td", text: /94.3 kg/
    get journal_path("2026-11-03")
    assert_select "h3", text: "5.0 mg"
    assert_select ".day-event", 1
    get journal_path("2026-11-06")
    assert_response :success
    assert_no_difference("DayNote.count") { get journal_path("2026-11-07") }
  end
  test "account isolation applies to mutations, charts, journal, imports and exports" do
    w = @user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-02T00:05:00-05:00")
    i = @user.injections.create!(dose: 5, occurred_at: "2026-11-03T09:00:00-05:00", notes: "private")
    @user.day_notes.create!(local_date: "2026-11-04", notes: "owner-only-note")
    batch = @user.import_batches.create!(payload: PersonalExport.new(@user).document)
    post session_path, params: { email_address: create_user("other@example.test").email_address, password: "test-password-123" }
    get edit_entry_path(w, kind: "weight"); assert_response :not_found
    patch entry_path(w, kind: "weight"), params: { entry: { value: 1, unit: "lb", local_time: "2026-11-02T00:00" } }; assert_response :not_found
    delete entry_path(i, kind: "injection"); assert_response :not_found
    get import_path(batch); assert_response :not_found
    post commit_import_path(batch); assert_response :not_found
    get root_path(range: "all"); assert_response :success; assert_select ".range-table tbody tr", 1
    get journal_path("2026-11-04"); refute_includes response.body, "owner-only-note"
    get export_path("json"); data = JSON.parse(response.body)
    assert data["records"].values.all?(&:empty?)
    %w[weights injections day_notes].each do |kind|
      get export_path(kind)
      assert_equal 1, CSV.parse(response.body).size
      assert_includes response.headers["Cache-Control"], "no-store"
    end
    assert_equal 200, w.reload.value
  end
  test "edits retain original timestamp precision and delete is scoped" do
    w = @user.weights.create!(value: "201.125", unit: "lb", occurred_at: "2026-11-01T23:55:42.123456-05:00")
    patch entry_path(w, kind: "weight"), params: { entry: { value: "200.25", unit: "kg", local_time: "2026-11-01T23:55" } }
    assert_response :see_other
    assert_equal "2026-11-01T23:55:42.123456-05:00", w.reload.occurred_at
    assert_equal "kg", @user.reload.preferred_unit
    assert_difference("Weight.count", -1) { delete entry_path(w, kind: "weight") }
  end
  test "invalid input returns reviewable errors and metric preferences can all be disabled" do
    post entries_path, params: { kind: "weight", entry: { id: SecureRandom.uuid, value: "-2", unit: "lb", local_time: "2026-11-02T12:00" } }
    assert_response :unprocessable_entity
    assert_select ".errors", text: /greater than 0/
    @user.update!(enabled_metrics: ["sleep_hours"])
    patch settings_path, params: { user: { preferred_unit: "kg", time_zone: "America/New_York", reminder_local: "2026-11-12T09:00" } }
    assert_response :see_other
    assert_equal [], @user.reload.enabled_metrics
    assert @user.reminder_at
    get root_path(range: "all")
    assert_select ".reminder"
    assert_equal [], Timeline.new(@user, range: "all").chart[:injections]
  end
  test "login required and public signup unavailable" do
    delete session_path
    get root_path; assert_redirected_to new_session_path
    get export_path("json"); assert_redirected_to new_session_path
    get "/signup"; assert_response :not_found
  end
end
