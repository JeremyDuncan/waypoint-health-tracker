require "test_helper"
class PersonalImportTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user.update!(preferred_unit: "kg", enabled_metrics: %w[appetite side_effects severity sleep_hours], reminder_at: "2026-11-12T09:30:00-05:00")
    @user.weights.create!(value: "94.1234", unit: "kg", occurred_at: "2026-11-02T00:05:42.123456-05:00")
    @user.weights.create!(value: "207.8", unit: "lb", occurred_at: "2026-11-02T08:20:00-05:00")
    @user.injections.create!(dose: 7.5, occurred_at: "2026-11-03T09:30:00-05:00", site: "Thigh", side: "Left", notes: "Actual injection\nsecond line")
    @user.day_notes.create!(local_date: "2026-11-04", notes: "Notes, with commas & 🌿", metrics: { "sleep_hours" => "7.5", "side_effects" => "None", "severity" => "0" })
  end
  test "JSON roundtrip preserves stable IDs, exact values units offsets notes definitions and preferences" do
    document = PersonalExport.new(@user).document
    assert_equal "waypoint-health.personal", document["schema"]
    refute_match(/password|digest|session|secret|email_address/, document.to_json)
    parsed = PersonalImport.parse_json(JSON.generate(document))
    target = create_user("target@example.test")
    importer = PersonalImport.new(target, parsed)
    report = importer.report
    assert_empty report["errors"]
    assert_equal 4, report["creates"]
    batch = target.import_batches.create!(payload: parsed)
    importer.commit!(batch, apply_preferences: true)
    roundtrip = PersonalExport.new(target.reload).document
    assert_equal document.except("exported_at"), roundtrip.except("exported_at")
    assert_equal 4, importer.report["duplicates"]
    assert_no_difference("Weight.count") do
      importer.commit!(batch)
      importer.commit!(target.import_batches.create!(payload: parsed))
    end
    target.weights.first.update!(value: "95.1")
    assert_equal 1, importer.report["conflicts"]
    assert_raises(ArgumentError) { importer.commit!(target.import_batches.create!(payload: parsed)) }
    assert_equal BigDecimal("95.1"), target.weights.first.value
  end
  test "legacy Hearth exports still import and deduplicate against renamed exports" do
    document = PersonalExport.new(@user).document
    legacy = document.merge("schema" => "hearth.personal")
    target = create_user("legacy@example.test")
    parsed = PersonalImport.parse_json(legacy.to_json)
    importer = PersonalImport.new(target, parsed)
    importer.commit!(target.import_batches.create!(payload: parsed), apply_preferences: true)
    assert_equal document.except("exported_at"), PersonalExport.new(target.reload).document.except("exported_at")
    renamed = PersonalImport.new(target, PersonalImport.parse_json(document.to_json))
    assert_equal 0, renamed.report["creates"]
    assert_equal 4, renamed.report["duplicates"]
    target.weights.first.update!(value: "96")
    assert_equal 1, PersonalImport.new(target, parsed).report["conflicts"]
    assert_raises(ArgumentError) { PersonalImport.parse_json(document.merge("schema" => "other.personal").to_json) }
  end
  test "preview commits atomically and detects edits after preview" do
    payload = PersonalExport.new(@user).document
    importer = PersonalImport.new(@user, payload)
    assert_equal 4, importer.report["duplicates"]
    @user.day_notes.first.update!(notes: "Edited since preview")
    assert_equal 1, importer.report["conflicts"]
    assert_raises(ArgumentError) { importer.commit!(@user.import_batches.create!(payload: payload)) }
  end
  test "CSV mapping flags ambiguous dates and missing units, reports source row and repeats are deduped" do
    text = "Date,Weight,Unit\n11/02/2026,201,lb\n2026-11-03T09:00:00-05:00,200,\n2026-11-04T09:00:00-05:00,199,lb\n"
    payload = PersonalImport.parse_csv(text, { "date_column" => "Date", "value_column" => "Weight", "unit_column" => "Unit", "date_format" => "iso" })
    target = create_user("csv@example.test")
    importer = PersonalImport.new(target, payload)
    assert_equal [2, 3], importer.report["errors"].map { |e| e["row"] }
    assert_equal 1, importer.report["creates"]
    assert_raises(ArgumentError) { importer.commit!(target.import_batches.create!(payload: payload)) }
    text = PersonalExport.new(@user).csv("weights")
    mapping = { "date_column" => "occurred_at", "value_column" => "value", "unit_column" => "unit", "id_column" => "id", "date_format" => "iso" }
    payload = PersonalImport.parse_csv(text, mapping)
    importer = PersonalImport.new(target, payload)
    assert_empty importer.report["errors"]
    importer.commit!(target.import_batches.create!(payload: payload))
    assert_equal 2, importer.report["duplicates"]
    target.weights.first.update!(value: "95")
    assert_equal 1, importer.report["conflicts"]
    no_ids = "Date,Weight\n2026-11-03T09:00:00-05:00,200\n2026-11-03T09:00:00-05:00,200\n"
    parsed = PersonalImport.parse_csv(no_ids, { "date_column" => "Date", "value_column" => "Weight", "unit" => "lb", "date_format" => "iso" })
    report = PersonalImport.new(target, parsed).report
    assert_equal 1, report["creates"]
    assert_equal 1, report["duplicates"]
  end
  test "date only mapping uses explicit format noon and offset" do
    payload = PersonalImport.parse_csv("date,weight\n02/11/2026,94.25\n", { "date_column" => "date", "value_column" => "weight", "unit" => "kg", "date_format" => "dmy", "offset" => "-05:00" })
    assert_empty payload["parse_errors"]
    assert_equal "2026-11-02T12:00:00-05:00", payload.dig("records", "weights", 0, "occurred_at")
  end
  test "bad units dates excessive precision unknown metrics and future schema versions are rejected" do
    assert_not @user.weights.build(value: "200.12345", unit: "lb", occurred_at: "2026-11-02T09:30:00-05:00").valid?
    assert_not @user.weights.build(value: "200", unit: "stone", occurred_at: "2026-02-30T09:30:00-05:00").valid?
    assert_not @user.day_notes.build(local_date: "2026-11-05", metrics: { "unknown" => 3 }).valid?
    document = PersonalExport.new(@user).document
    invalid_id = Marshal.load(Marshal.dump(document))
    invalid_id["records"]["weights"][0]["id"] = nil
    assert PersonalImport.new(@user, invalid_id).report["errors"].any?
    document["version"] = 2
    assert_raises(ArgumentError) { PersonalImport.parse_json(document.to_json) }
  end
  test "throttling persists by key" do
    10.times { assert LoginAttempt.allowed?("test-key") }
    assert_not LoginAttempt.allowed?("test-key")
    travel 16.minutes do
      assert LoginAttempt.allowed?("test-key")
    end
  end
end
