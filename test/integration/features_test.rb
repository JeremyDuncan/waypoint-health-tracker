require "test_helper"
require "pdf/reader"

class FeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    login(@user)
    @user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-09T08:00:00-05:00")
    @user.weights.create!(value: 90, unit: "kg", occurred_at: "2026-11-12T08:00:00-05:00")
    @user.injections.create!(dose: 5, site: "Thigh", side: "Left", occurred_at: "2026-11-10T09:00:00-05:00", notes: "private-injection-note")
    @user.day_notes.create!(local_date: "2026-11-11", notes: "private-journal-note café 🌿", metrics: { "side_effects" => "Mild nausea", "severity" => 2 })
  end

  test "goals can be saved edited cleared and reject invalid targets without losing readings" do
    patch goal_path, params: { goal: { mode: "target", value: "180", unit: "lb", start_date: "2026-11-09" } }
    assert_redirected_to goal_path
    assert_equal "180.0", @user.reload.weight_goal["value"]
    get goal_path
    assert_response :success
    assert_select "progress"
    patch goal_path, params: { goal: { mode: "target", value: "-2", unit: "lb", start_date: "2026-11-09" } }
    assert_response :unprocessable_entity
    assert_equal "180.0", @user.reload.weight_goal["value"]
    assert_no_difference("Weight.count") { delete goal_path }
    assert_nil @user.reload.weight_goal
  end

  test "height conversion and invalid edits are atomic and modal errors retain typed values" do
    goal = { mode: "target", value: "180", unit: "lb", start_date: "2026-11-09" }
    patch goal_path, params: { goal: goal, height_value: "70", height_unit: "in" }
    assert_redirected_to goal_path
    assert_equal BigDecimal("177.8"), @user.reload.height_cm
    get goal_path
    assert_select '[aria-label="Current weight"]', text: /198.4 lb/
    assert_select '[aria-label="Current BMI"]', text: /28.5/
    assert_select '[aria-label="Weight change since goal start"]', text: /Lost/
    assert_select 'dialog[aria-labelledby="goal-dialog-title"]'
    # Height is stored in cm but shown back in inches, the default unit.
    assert_select 'input[name="height_value"][value="70"]'
    assert_select 'select[name="height_unit"] option[selected][value="in"]'
    assert_select '[aria-label="Current BMI"]', text: /Using height 70 in/
    patch goal_path, params: { goal: goal.merge(value: "170"), height_value: "-2", height_unit: "cm" }
    assert_response :unprocessable_entity
    assert_equal "180.0", @user.reload.weight_goal["value"]
    assert_equal BigDecimal("177.8"), @user.height_cm
    assert_select '[data-modal-open-value="true"]'
    assert_select 'input[name="height_value"][value="-2"]'
  end

  test "appointment preview and PDF honor dates and optional notes and metrics with no account metadata" do
    options = { range: "custom", from: "2026-11-09", to: "2026-11-12" }
    get report_path, params: options
    assert_response :success
    assert_not_includes response.body, "private-injection-note"
    assert_not_includes response.body, "private-journal-note"
    assert_includes response.body, "Mild nausea"
    get report_path(format: :pdf), params: options
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Cache-Control"], "no-store"
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    assert_includes text, "Thigh / Left"
    assert_includes text, "90.0 kg"
    assert_includes text, "Mild nausea"
    assert_not_includes text, "private-journal-note"
    assert_not_includes text, "private-injection-note"
    assert_not_includes text, @user.email_address
    get report_path(format: :pdf), params: options.merge(include_notes: "1", include_metrics: "0")
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    assert_includes text, "private-journal-note café"
    assert_includes text, "🌿"
    assert_includes text, "private-injection-note"
    assert_not_includes text, "Mild nausea"
    get report_path(format: :pdf), params: options.merge(from: "2026-11-11")
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    assert_not_includes text, "Thigh / Left"
    get report_path, params: options.merge(from: "2021-01-01")
    assert_response :unprocessable_entity
  end

  test "new pages and PDFs remain scoped to the signed-in account and require authentication" do
    post session_path, params: { email_address: create_user("other@example.test").email_address, password: "test-password-123" }
    get report_path(format: :pdf), params: { range: "custom", from: "2026-11-09", to: "2026-11-12", include_notes: "1" }
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    assert_includes text, "No weigh-ins"
    assert_not_includes text, "private-journal-note"
    assert_not_includes text, "Thigh / Left"
    get review_path(week: "2026-11-09")
    assert_response :success
    assert_not_includes response.body, "private-journal-note"
    delete session_path
    [goal_path, review_path, report_path, report_path(format: :pdf)].each do |path|
      get path
      assert_redirected_to new_session_path
    end
  end

  test "long appointment notes flow across PDF pages without truncation" do
    note = @user.day_notes.first
    note.update!(notes: "Beginning of a long note. " + ("A recorded observation. " * 350) + " End of the long note.")
    get report_path(format: :pdf), params: { range: "custom", from: "2026-11-09", to: "2026-11-12", include_notes: "1" }
    assert_response :success
    pages = PDF::Reader.new(StringIO.new(response.body)).pages
    assert_operator pages.size, :>, 1
    text = pages.map(&:text).join("\n")
    assert_includes text, "Beginning of a long note."
    assert_includes text, "End of the long note."
    assert_includes text, "Exact weigh-ins"
  end
end
