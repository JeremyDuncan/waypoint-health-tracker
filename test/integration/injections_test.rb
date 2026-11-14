require "test_helper"

class InjectionsTest < ActionDispatch::IntegrationTest
  test "page is private, scoped to the signed-in user, and works without measurements" do
    get injections_path
    assert_redirected_to new_session_path
    user = create_user
    other = create_user("other@example.test")
    own = user.injections.create!(dose: 5, occurred_at: "2026-11-01T09:00:00-05:00", site: "Thigh", side: "Left", notes: "own-shot-note")
    other.injections.create!(dose: 15, occurred_at: "2026-11-02T09:00:00-05:00", site: "Upper arm", side: "Right", notes: "private-other-shot")
    login(user)
    get injections_path(range: "all")
    assert_response :success
    assert_select "h1", text: "Injections."
    assert_select "details.shot-card", 1
    assert_select "#shot-#{own.id}", 1
    assert_includes response.body, "own-shot-note"
    refute_includes response.body, "private-other-shot"
    assert_select "[data-shot-status='no_baseline']", 1
    assert_includes response.headers["Cache-Control"], "no-store"
    get injections_path(site: "Thigh", range: "all")
    assert_response :success
    assert_select "details.shot-card", 1
    get injections_path(site: "Upper arm", range: "all")
    assert_select "details.shot-card", 0
    assert_select ".insights-empty", 1
  end

  test "filters fail with a usable page and navigation links to injection history" do
    login(create_user)
    get injections_path(dose: "bogus")
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /Choose a listed dose/
    assert_select ".insights-empty", 1
    get root_path
    assert_select 'nav[aria-label="Main navigation"] a[href="/injections"]', text: "Injections"
  end
end
