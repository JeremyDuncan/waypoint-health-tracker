require "test_helper"

class ChartPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    login(@user)
  end

  test "saved page filters survive fresh sessions and partial view updates without resetting each other" do
    injection = { range: "custom", from: "2026-11-01", to: "2026-11-14", site: "Thigh", side: "Left", dose: "5", grouping: "site", mode: "aligned" }
    patch chart_preferences_path(page: "injections"), params: { preferences: injection }
    assert_redirected_to injections_path
    get injections_path
    assert_select 'input[name="preferences[from]"][value="2026-11-01"]'
    assert_select 'select[name="preferences[site]"] option[selected][value="Thigh"]'
    before = @user.reload.chart_preferences["injections"].dup
    patch chart_preferences_path(page: "injections"), params: { preferences: { mode: "calendar" } }, as: :json
    assert_response :success
    assert_equal before.merge("mode" => "calendar"), @user.reload.chart_preferences["injections"]
    patch chart_preferences_path(page: "overview"), params: { preferences: { range: "7", mode: "monthly", trend: true, weight: false } }, as: :json
    assert_response :success
    assert_equal "Thigh", @user.reload.chart_preferences.dig("injections", "site")
    delete session_path
    login(@user)
    get root_path
    assert_select '[data-timeline-target="mode"] option[selected][value="monthly"]'
    assert_select 'input[data-timeline-target="trendToggle"][checked]'
    assert_select 'input[data-timeline-target="weightToggle"][checked]', 0
    # Dates are relative for presets, not frozen to the day settings were saved.
    travel_to Time.iso8601("2026-12-20T12:00:00-05:00") do
      login(@user)
      get root_path
      assert_select 'input[name="preferences[from]"][value="2026-12-14"]'
      assert_select 'input[name="preferences[to]"][value="2026-12-20"]'
    end
  end

  test "defaults clear only one page and invalid filters preserve existing settings" do
    patch chart_preferences_path(page: "overview"), params: { preferences: { range: "90", mode: "weekly" } }, as: :json
    patch chart_preferences_path(page: "injections"), params: { preferences: { site: "Thigh", mode: "aligned" } }, as: :json
    before = @user.reload.chart_preferences.deep_dup
    patch chart_preferences_path(page: "injections"), params: { preferences: { range: "custom", from: "2026-11-14", to: "2026-11-01" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal before, @user.reload.chart_preferences
    patch chart_preferences_path(page: "overview"), params: { preferences: { range: "custom", from: "2026-11-14", to: "2026-11-01" } }
    assert_response :see_other
    follow_redirect!
    assert_response :unprocessable_entity
    assert_select '[data-modal-open-value="true"]'
    assert_select 'input[name="preferences[from]"][value="2026-11-14"]'
    assert_equal before, @user.reload.chart_preferences
    delete chart_preferences_path(page: "injections")
    assert_redirected_to injections_path
    assert_equal before.except("injections"), @user.reload.chart_preferences
    get injections_path
    assert_select 'select[name="preferences[range]"] option[selected][value="90"]'
  end

  test "chart preferences are isolated per user and require authenticated mutations" do
    patch chart_preferences_path(page: "injections"), params: { preferences: { site: "Thigh" } }, as: :json
    own = @user.reload.chart_preferences.deep_dup
    other = create_user("other@example.test")
    login(other)
    get injections_path
    assert_select 'select[name="preferences[site]"] option[selected][value="all"]'
    patch chart_preferences_path(page: "injections"), params: { preferences: { site: "Upper arm" } }, as: :json
    assert_equal own, @user.reload.chart_preferences
    delete chart_preferences_path(page: "injections")
    assert_equal own, @user.reload.chart_preferences
    delete session_path
    patch chart_preferences_path(page: "overview"), params: { preferences: { mode: "weekly" } }, as: :json
    assert_response :unauthorized
  end

  test "saved filters export and reimport with preferences while legacy documents keep current settings" do
    patch chart_preferences_path(page: "overview"), params: { preferences: { range: "7", mode: "monthly", trend: true } }, as: :json
    source = PersonalExport.new(@user.reload).document
    target = create_user("target@example.test")
    payload = PersonalImport.parse_json(source.to_json)
    importer = PersonalImport.new(target, payload)
    assert_empty importer.report["errors"]
    importer.commit!(target.import_batches.create!(payload: payload), apply_preferences: true)
    assert_equal @user.chart_preferences, target.reload.chart_preferences
    source["preferences"].delete("chart_preferences")
    old_payload = PersonalImport.parse_json(source.to_json)
    old = PersonalImport.new(target, old_payload)
    old.commit!(target.import_batches.create!(payload: old_payload), apply_preferences: true)
    assert_equal @user.chart_preferences, target.reload.chart_preferences
    source["preferences"]["chart_preferences"] = { "injections" => { "site" => "not a site" } }
    assert PersonalImport.new(target, PersonalImport.parse_json(source.to_json)).report["errors"].any?
  end

  test "chart preference writes require a CSRF token when protection is enabled" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    patch chart_preferences_path(page: "overview"), params: { preferences: { mode: "weekly" } }, as: :json
    assert_response :unprocessable_entity
    assert_empty @user.reload.chart_preferences
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
