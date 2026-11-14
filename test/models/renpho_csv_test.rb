require "test_helper"

class RenphoCsvTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @csv = "No.,Date,Time,Weight(lb),BMI,Remarks\n1,2026.11.03,06:30:18,200.4,27.0,--\n2,2026.10.31,06:45:03,201.2,27.1,--\n"
  end

  test "recognizes Renpho columns and preserves units seconds and per-reading daylight-saving offsets" do
    assert RenphoCsv.detect?(CSV.parse_line(@csv))
    payload = RenphoCsv.parse(@csv, time_zone: @user.time_zone)
    assert_empty payload["parse_errors"]
    assert_equal "America/New_York", payload["time_zone"]
    assert_equal "lb", payload["weight_unit"]
    readings = payload.dig("records", "weights")
    assert_equal "2026-11-03T06:30:18-05:00", readings[0]["occurred_at"]
    assert_equal "2026-10-31T06:45:03-04:00", readings[1]["occurred_at"]
    assert_equal "200.4", readings[0]["value"]
    assert_equal "lb", readings[0]["unit"]
    assert_equal [], payload.dig("records", "day_notes")
    assert_equal [], payload.dig("records", "injections")
  end

  test "reexports reordered rows and changed sequence numbers do not duplicate and edits become conflicts" do
    payload = RenphoCsv.parse(@csv, time_zone: @user.time_zone)
    importer = PersonalImport.new(@user, payload)
    assert_equal 2, importer.report["creates"]
    assert_empty importer.report["errors"]
    importer.commit!(@user.import_batches.create!(payload: payload))
    reordered = @csv.lines.first + "99,2026.10.31,06:45:03,201.2,27.1,--\n98,2026.11.03,06:30:18,200.4,27.0,--\n"
    repeat = RenphoCsv.parse(reordered, time_zone: @user.time_zone)
    assert_equal 2, PersonalImport.new(@user, repeat).report["duplicates"]
    assert_no_difference("Weight.count") { PersonalImport.new(@user, repeat).commit!(@user.import_batches.create!(payload: repeat)) }
    @user.weights.order(:recorded_at).first.update!(value: "199")
    assert_equal 1, PersonalImport.new(@user, repeat).report["conflicts"]
    assert_raises(ArgumentError) { PersonalImport.new(@user, repeat).commit!(@user.import_batches.create!(payload: repeat)) }
    source_edit = RenphoCsv.parse(@csv.sub("200.4", "198.4"), time_zone: @user.time_zone)
    assert_equal payload.dig("records", "weights", 0, "id"), source_edit.dig("records", "weights", 0, "id")
    assert_equal 2, PersonalImport.new(@user, source_edit).report["conflicts"]
  end

  test "kg unit comes from the header and changing the import zone preserves source IDs" do
    kg = RenphoCsv.parse(@csv.sub("Weight(lb)", "Weight(kg)"), time_zone: "Europe/London")
    assert_equal "kg", kg.dig("records", "weights", 0, "unit")
    assert_equal "2026-11-03T06:30:18+00:00", kg.dig("records", "weights", 0, "occurred_at")
    pounds = RenphoCsv.parse(@csv, time_zone: @user.time_zone)
    assert_equal pounds.dig("records", "weights", 0, "id"), kg.dig("records", "weights", 0, "id")
  end

  test "invalid ambiguous and nonexistent clock times and missing weights have row errors" do
    csv = "No.,Date,Time,Weight(lb)\n1,2026.02.30,06:30:00,200\n2,2026.11.01,01:30:00,200\n3,2026.03.08,02:30:00,200\n4,2026.11.03,06:00:00,\n"
    payload = RenphoCsv.parse(csv, time_zone: @user.time_zone)
    assert_equal [2, 3, 4, 5], payload["parse_errors"].map { |error| error["row"] }
    assert_match(/occurs twice/, payload["parse_errors"][1]["message"])
    assert_match(/does not exist/, payload["parse_errors"][2]["message"])
    assert_raises(ArgumentError) { RenphoCsv.parse(@csv, time_zone: "Unknown/Zone") }
    assert_raises(ArgumentError) { RenphoCsv.parse(@csv.sub("Weight(lb)", "Weight"), time_zone: @user.time_zone) }
  end
end
