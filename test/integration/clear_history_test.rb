require "test_helper"

class ClearHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @other = create_user("other@example.test")
    [@user, @other].each { |user| add_history(user) }
    login(@user)
  end

  test "settings asks for confirmation in a modal that shows what will be deleted" do
    get settings_path
    assert_response :success
    assert_select "dialog[aria-labelledby=clear-history-title]" do
      assert_select "strong", text: "1 weigh-in, 1 injection, and 1 journal day"
      assert_select "a[href=?]", export_path("json")
      assert_select "form[action=?]", settings_history_path do
        assert_select "input[name=_method][value=delete]"
        assert_select "input[name=confirmation][required]"
        assert_select "input[type=submit][disabled]"
      end
    end
    assert_select "[data-modal-open-value=true]", count: 0
  end

  test "confirming deletes only this account's history and keeps its account, preferences and goal" do
    goal = { "mode" => "target", "value" => "180", "unit" => "lb", "start_date" => "2026-11-01", "low" => nil, "high" => nil }
    @user.update!(weight_goal: goal, height_cm: 180, reminder_at: 1.day.from_now, preferred_unit: "kg")
    preferences = @user.reload.preferences
    digest = @user.password_digest

    assert_no_difference ["User.count", "Session.count"] do
      delete settings_history_path, params: { confirmation: "DELETE" }
    end
    assert_redirected_to settings_path
    follow_redirect!
    assert_select ".flash.notice", text: "Health history cleared."
    assert_equal [0, 0, 0, 0], history_counts(@user)
    assert_equal [1, 1, 1, 1], history_counts(@other)
    assert_equal preferences, @user.reload.preferences
    assert_equal digest, @user.password_digest
    [root_path, review_path, goal_path, injections_path, calendar_path, report_path].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "an exported history can be imported again after clearing" do
    document = PersonalExport.new(@user).document
    delete settings_history_path, params: { confirmation: "DELETE" }
    file = Rack::Test::UploadedFile.new(StringIO.new(JSON.generate(document)), "application/json", original_filename: "export.json")
    post imports_path, params: { format_kind: "json", file: file }
    post commit_import_path(@user.import_batches.sole)
    assert_redirected_to settings_path
    assert_equal document["records"], PersonalExport.new(@user.reload).document["records"]
  end

  test "a missing or wrong confirmation deletes nothing and reopens the modal" do
    [{}, { confirmation: "" }, { confirmation: "delete" }, { confirmation: "DELETE everything" }, { confirmation: { x: "DELETE" } }].each do |params|
      delete settings_history_path, params: params
      assert_response :unprocessable_entity
      assert_select "[data-modal-open-value=true] dialog .errors", text: /Nothing was deleted/
      assert_equal [1, 1, 1, 1], history_counts(@user)
    end
  end

  test "signed-out requests delete nothing" do
    delete session_path
    delete settings_history_path, params: { confirmation: "DELETE" }
    assert_redirected_to new_session_path
    assert_equal [1, 1, 1, 1], history_counts(@user)
  end

  test "clearing requires CSRF protection" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    delete settings_history_path, params: { confirmation: "DELETE" }
    assert_response :unprocessable_entity
    assert_equal [1, 1, 1, 1], history_counts(@user)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  private

  def add_history(user)
    user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-11-01T12:00:00-05:00")
    user.injections.create!(dose: 5, site: "Thigh", side: "Left", occurred_at: "2026-11-01T13:00:00-05:00")
    user.day_notes.create!(local_date: "2026-11-01", notes: "Private note")
    user.import_batches.create!(payload: { "csv" => "date,weight" })
  end

  def history_counts(user)
    [user.weights.count, user.injections.count, user.day_notes.count, user.import_batches.count]
  end
end
