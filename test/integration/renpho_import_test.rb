require "test_helper"

class RenphoImportTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    login(@user)
  end

  test "Renpho CSV auto-detects on upload and offers a scoped timezone-aware preview before committing" do
    file = Rack::Test::UploadedFile.new(Rails.root.join("docs/examples/renpho-weights.csv"), "text/csv")
    assert_no_difference("Weight.count") { post imports_path, params: { format_kind: "csv", file: file } }
    assert_response :see_other
    batch = @user.import_batches.order(:created_at).last
    assert_equal "renpho", batch.payload["source_format"]
    follow_redirect!
    assert_select "h2", text: "Renpho export detected"
    assert_select ".import-counts", text: /2 creates.*0 duplicates.*0 conflicts.*0 errors/m
    assert_select 'select[name="time_zone"] option[selected]', value: "America/New_York"
    post preview_import_path(batch), params: { time_zone: "Europe/London" }
    assert_response :see_other
    assert_equal "Europe/London", batch.reload.payload["time_zone"]
    assert_equal "2026-11-03T06:30:18+00:00", batch.payload.dig("records", "weights", 0, "occurred_at")
    assert_difference("@user.weights.count", 2) { post commit_import_path(batch) }
    assert_response :see_other
    assert_no_difference("Weight.count") { post commit_import_path(batch) }
    other = create_user("other@example.test")
    login(other)
    get import_path(batch)
    assert_response :not_found
    post commit_import_path(batch)
    assert_response :not_found
    assert_empty other.weights
  end
end
