require "test_helper"
class TimeAndSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    login(@user)
  end
  test "repeated DST hour requires explicit offset and nonexistent time is rejected" do
    body = { kind: "weight", entry: { id: SecureRandom.uuid, value: "200", unit: "lb", local_time: "2026-11-01T01:30" } }
    assert_no_difference("Weight.count") { post entries_path, params: body }
    assert_response :unprocessable_entity
    assert_select ".errors", text: /occurs twice/
    body[:entry][:utc_offset] = "-04:00"
    post entries_path, params: body
    assert_response :see_other
    assert_equal "2026-11-01T01:30:00-04:00", @user.weights.last.occurred_at
    body[:entry] = body[:entry].merge(id: SecureRandom.uuid, utc_offset: "", local_time: "2026-03-08T02:30")
    post entries_path, params: body
    assert_response :unprocessable_entity
    assert_select ".errors", text: /does not exist/
    body[:entry][:local_time] = "2026-02-30T12:00"
    post entries_path, params: body
    assert_response :unprocessable_entity
  end
  test "request privacy headers and fresh nonempty CSP nonce" do
    get root_path
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_match(/'nonce-[A-Za-z0-9+\/=]+'/ , response.headers["Content-Security-Policy"])
    nonce = response.headers["Content-Security-Policy"]
    get root_path
    assert_not_equal nonce, response.headers["Content-Security-Policy"]
  end
  test "missing CSRF token is rejected when protection is enabled" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post entries_path, params: { kind: "weight", entry: { id: SecureRandom.uuid, value: "200", unit: "lb", local_time: "2026-11-02T12:00" } }
    assert_response :unprocessable_entity
    assert_equal 0, @user.weights.count
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
