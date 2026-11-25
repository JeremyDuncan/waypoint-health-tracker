require "csv"
class PersonalImport
  KINDS = { "weights" => Weight, "injections" => Injection, "day_notes" => DayNote }.freeze
  def self.stable_id(source)
    digest = Digest::SHA256.hexdigest(source)
    [digest[0,8], digest[8,4], digest[12,4], digest[16,4], digest[20,12]].join("-")
  end
  def self.parse_json(text)
    data = JSON.parse(text)
    raise ArgumentError, "Expected Waypoint Health personal JSON version 1" unless data.is_a?(Hash) && %w[waypoint-health.personal hearth.personal].include?(data["schema"]) && data["version"] == 1
    raise ArgumentError, "Metric definitions are missing or unsupported" unless data["metric_definitions"] == MetricDefinitions::ALL
    raise ArgumentError, "Records must contain weights, injections and day_notes arrays" unless data["records"].is_a?(Hash) && data["records"].keys.sort == KINDS.keys.sort && data["records"].values.all? { |v| v.is_a?(Array) }
    raise ArgumentError, "Preferences are missing" unless data["preferences"].is_a?(Hash)
    data.slice("records", "preferences", "metric_definitions")
  end
  def self.parse_csv(text, mapping)
    rows = CSV.parse(text, headers: true)
    raise ArgumentError, "CSV must have unique, nonblank headers" if rows.headers.any?(&:blank?) || rows.headers.uniq != rows.headers
    %w[date_column value_column].each do |field|
      raise ArgumentError, "Map #{field.humanize.downcase}" unless rows.headers.include?(mapping[field])
    end
    records = []; errors = []
    rows.each_with_index do |row, index|
      begin
        date = row[mapping["date_column"]].to_s.strip
        stamp = case mapping["date_format"]
        when "iso"
          raise ArgumentError, "Ambiguous date: use ISO 8601 with seconds and explicit offset, or choose a local date format" unless date.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/)
          Time.iso8601(date)
          date
        when "ymd", "mdy", "dmy"
          format = { "ymd" => "%Y-%m-%d", "mdy" => "%m/%d/%Y", "dmy" => "%d/%m/%Y" }.fetch(mapping["date_format"])
          offset = mapping["offset"].to_s
          raise ArgumentError, "Choose an explicit UTC offset, such as -05:00. Split files across daylight-saving offsets." unless offset.match?(/\A[+-](?:0\d|1[0-4]):[0-5]\d\z/)
          # Date-only imports use local noon, disclosed in the mapping preview.
          parsed = Date.strptime(date, format)
          raise ArgumentError, "Date does not match the selected format" unless parsed.strftime(format) == date
          "#{parsed.iso8601}T12:00:00#{offset}"
        else raise ArgumentError, "Choose a date format"
        end
        unit = mapping["unit_column"].present? ? row[mapping["unit_column"]].to_s.strip.downcase : mapping["unit"]
        raise ArgumentError, "Ambiguous unit: map a unit column or explicitly choose lb/kg" unless %w[lb kg].include?(unit)
        value = BigDecimal(row[mapping["value_column"]].to_s, exception: false)
        raise ArgumentError, "Weight must be a positive decimal number" unless value && value.finite? && value > 0
        attrs = { "occurred_at" => stamp, "value" => value.to_s("F"), "unit" => unit }
        uuid = mapping["id_column"].present? ? row[mapping["id_column"]].to_s : nil
        uuid = stable_id(JSON.generate(attrs)) if uuid.blank?
        records << attrs.merge("id" => uuid, "_row" => index + 2)
      rescue ArgumentError, Date::Error => e
        errors << { "row" => index + 2, "message" => e.message }
      end
    end
    { "records" => { "weights" => records, "injections" => [], "day_notes" => [] }, "parse_errors" => errors }
  end
  def initialize(user, payload)
    @user, @payload = user, payload
  end
  def report
    seen = {}; seen_days = {}; seen_content = {}
    result = { "rows" => [], "errors" => (@payload["parse_errors"] || []).dup,
      "creates" => 0, "duplicates" => 0, "conflicts" => 0 }
    KINDS.each do |kind, klass|
      existing_content = @user.public_send(kind).to_a.to_h { |saved| [content_key(saved), true] }
      Array(@payload.dig("records", kind)).each_with_index do |raw, index|
        row_number = raw.is_a?(Hash) ? (raw["_row"] || index + 1) : index + 1
        unless raw.is_a?(Hash) && raw["id"].is_a?(String) && (raw.keys - ["_row"]).sort == PersonalExport::FIELDS[kind].sort
          result["errors"] << { "row" => row_number, "message" => "#{kind}: unknown fields or invalid record" }
          next
        end
        attrs = raw.except("_row")
        attrs = attrs.merge("uuid" => attrs.delete("id"))
        record = klass.new(attrs.merge(user: @user))
        unless record.valid?
          # Uniqueness is classified below as a duplicate or conflict.
          validation_errors = record.errors.reject { |e| e.type == :taken }.map(&:full_message)
          if validation_errors.any?
            result["errors"] << { "row" => row_number, "message" => "#{kind}: #{validation_errors.join(', ')}" }
            next
          end
        end
        existing = @user.public_send(kind).find_by(uuid: record.uuid)
        existing ||= @user.day_notes.find_by(local_date: record.local_date) if kind == "day_notes"
        canonical = record.portable
        content = content_key(record)
        previous = seen[[kind, record.uuid]]
        previous ||= seen_days[record.local_date] if kind == "day_notes"
        status = if existing
          content_key(existing) == content ? "duplicates" : "conflicts"
        elsif previous
          previous == content ? "duplicates" : "conflicts"
        elsif existing_content[content] || seen_content[[kind, content]]
          # The same event saved under another ID, such as a manually logged
          # entry that was also restored from a file.
          "duplicates"
        else
          "creates"
        end
        seen_content[[kind, content]] = true if status == "creates"
        seen[[kind, record.uuid]] = content
        seen_days[record.local_date] = content if kind == "day_notes"
        result[status] += 1
        result["rows"] << { "row" => row_number, "kind" => kind, "status" => status, "data" => canonical }
      end
    end
    if @payload["preferences"]
      preferences = @payload["preferences"]
      allowed = %w[preferred_unit time_zone enabled_metrics reminder_at]
      if (preferences.keys - %w[weight_goal height_cm chart_preferences]).sort != allowed.sort
        result["errors"] << { "row" => "preferences", "message" => "Expected exactly #{allowed.join(', ')}" }
      else
        reminder = preferences["reminder_at"]
        if !reminder.nil? && (!reminder.is_a?(String) || !reminder.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})\z/) || !valid_reminder?(reminder))
          result["errors"] << { "row" => "preferences", "message" => "Reminder must be an ISO timestamp with an offset or null" }
        end
        candidate = User.new(@user.attributes.except("id", "created_at", "updated_at").merge(preferences))
        candidate.valid?
        errors = candidate.errors.reject { |e| e.attribute == :email_address }.map(&:full_message)
        result["errors"] << { "row" => "preferences", "message" => errors.join(", ") } if errors.any?
      end
      result["preferences"] = preferences
    end
    result
  rescue ActiveRecord::SerializationTypeMismatch, ActiveModel::UnknownAttributeError, TypeError => e
    { "rows" => [], "errors" => [{ "row" => "file", "message" => "Invalid record structure" }], "creates" => 0, "duplicates" => 0, "conflicts" => 0 }
  end
  # Identifies the entry itself, independent of its ID and of how its timestamp
  # or blank optional fields happen to be written.
  def content_key(record)
    case record
    when Weight then [record.recorded_at, record.value, record.unit]
    when Injection then [record.recorded_at, record.dose, record.site.presence, record.side.presence, record.notes.presence]
    when DayNote then [record.local_date, record.notes.presence, record.metrics]
    end
  end
  def valid_reminder?(value)
    Date.iso8601(value[0, 10])
    Time.iso8601(value)
    true
  rescue ArgumentError
    false
  end
  def commit!(batch, apply_preferences: false)
    @user.with_lock do
      batch.reload
      raise ArgumentError, "This preview expired. Upload the file again." if batch.expired?
      return if batch.committed_at
      # Re-read inside the write transaction: edits since preview become conflicts.
      @payload = batch.payload
      preview = report
      raise ArgumentError, "Resolve validation errors and conflicts before committing. Existing records are never overwritten." if preview["errors"].any? || preview["conflicts"] > 0
      # Only new rows are written; duplicates are skipped.
      preview["rows"].select { |row| row["status"] == "creates" }.each do |row|
        attrs = row["data"].dup
        attrs["uuid"] = attrs.delete("id")
        @user.public_send(row["kind"]).create!(attrs)
      end
      @user.update!(preview["preferences"]) if apply_preferences && preview["preferences"]
      batch.update!(committed_at: Time.current)
      preview
    end
  end
end
