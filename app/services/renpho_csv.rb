require "csv"

class RenphoCsv
  WEIGHT_HEADER = /\AWeight\s*\((lb|kg)\)\z/i

  def self.detect?(headers)
    headers = Array(headers).map { |header| header.to_s.strip }
    %w[Date Time].all? { |field| headers.include?(field) } && headers.count { |field| WEIGHT_HEADER.match?(field) } == 1
  end

  def self.parse(text, time_zone:)
    zone = Time.find_zone(time_zone)
    raise ArgumentError, "Choose the time zone used by your Renpho readings" unless zone
    rows = CSV.parse(text.delete_prefix("\uFEFF"), headers: true, header_converters: ->(header) { header.strip })
    headers = rows.headers
    unless detect?(headers) && headers.uniq == headers && headers.none?(&:blank?)
      raise ArgumentError, "Renpho CSV needs Date, Time, and one Weight(lb) or Weight(kg) column"
    end
    weight_column = headers.find { |header| WEIGHT_HEADER.match?(header) }
    unit = WEIGHT_HEADER.match(weight_column)[1].downcase
    records = []
    errors = []
    rows.each_with_index do |row, index|
      begin
        local = "#{row['Date'].to_s.strip} #{row['Time'].to_s.strip}"
        raise ArgumentError, "Expected Renpho date YYYY.MM.DD and time HH:MM:SS" unless local.match?(/\A\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\z/)
        parts = DateTime.strptime(local, "%Y.%m.%d %H:%M:%S")
        raise ArgumentError, "Date or time is invalid" unless parts.strftime("%Y.%m.%d %H:%M:%S") == local
        wall_clock = Time.utc(parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second)
        periods = zone.tzinfo.periods_for_local(wall_clock)
        raise ArgumentError, "This time does not exist in #{zone.tzinfo.identifier} because clocks moved forward" if periods.empty?
        raise ArgumentError, "This time occurs twice in #{zone.tzinfo.identifier}. Import this row as an ISO timestamp with its actual UTC offset using the generic weight CSV importer" if periods.length > 1
        timestamp = Time.new(parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second, periods.first.observed_utc_offset).iso8601
        value = BigDecimal(row[weight_column].to_s.strip, exception: false)
        raise ArgumentError, "Weight must be a positive decimal number" unless value && value.finite? && value > 0
        # Renpho's No. column changes when a new export is sorted or extended.
        # Wall-clock measurement identity stays stable across value/unit edits.
        records << { "id" => PersonalImport.stable_id("renpho:v1:#{parts.strftime('%Y-%m-%dT%H:%M:%S')}"),
          "occurred_at" => timestamp, "value" => value.to_s("F"), "unit" => unit, "_row" => index + 2 }
      rescue ArgumentError, Date::Error => e
        errors << { "row" => index + 2, "message" => e.message }
      end
    end
    { "source_format" => "renpho", "time_zone" => zone.tzinfo.identifier, "weight_unit" => unit,
      "records" => { "weights" => records, "injections" => [], "day_notes" => [] }, "parse_errors" => errors }
  end
end
