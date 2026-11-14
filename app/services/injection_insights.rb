class InjectionInsights
  BASELINE_DAYS = 3
  FOLLOWUP_DAYS = 7
  SITES = ["Abdomen", "Thigh", "Upper arm", "Not recorded"].freeze
  SIDES = ["Left", "Right", "Not recorded"].freeze
  DOSES = [2.5, 5, 7.5, 10, 12.5, 15].map { |dose| BigDecimal(dose.to_s) }.freeze

  attr_reader :range, :rows, :unit, :site, :side, :dose, :grouping, :locations,
    :site_groups, :dose_groups, :compared_rows, :mean_change, :overall_change,
    :first_reading, :last_reading, :open_count

  def initialize(user, options = {}, now: Time.current)
    @user, @now, @unit = user, now, user.preferred_unit
    @zone = Time.find_zone!(user.time_zone)
    @site = options[:site].presence || "all"
    @side = options[:side].presence || "all"
    @grouping = options[:grouping].presence || "site_side"
    raise ArgumentError, "Choose a listed injection site" unless (["all", "unknown"] + SITES.first(3)).include?(site)
    raise ArgumentError, "Choose a listed injection side" unless %w[all unknown Left Right].include?(side)
    raise ArgumentError, "Choose a listed location comparison" unless %w[site site_side].include?(grouping)
    if options[:dose].present? && options[:dose] != "all"
      @dose = BigDecimal(options[:dose].to_s, exception: false)
      raise ArgumentError, "Choose a listed dose" unless DOSES.include?(dose)
    end
    @range = Time.use_zone(@zone) do
      Timeline.new(user, options.slice(:range, :from, :to).merge(range: options[:range].presence || "90"))
    end

    # Boundaries use the full actual injection history, even when a location or
    # dose filter hides the next shot. A reminder is never a boundary or a shot.
    history = user.injections.order(:recorded_at, :id).to_a
    positions = history.each_with_index.to_h { |shot, index| [shot.id, index] }
    selected = range.injections.sort_by { |shot| [shot.recorded_at, shot.id] }.select do |shot|
      (site == "all" || (site == "unknown" ? shot.site.blank? : shot.site == site)) &&
        (side == "all" || (side == "unknown" ? shot.side.blank? : shot.side == side)) &&
        (dose.nil? || shot.dose == dose)
    end
    readings = if selected.any?
      start = selected.first.recorded_at.in_time_zone(@zone) - BASELINE_DAYS.days
      finish = [selected.last.recorded_at.in_time_zone(@zone) + FOLLOWUP_DAYS.days, now].min
      user.weights.where(recorded_at: start..finish).order(:recorded_at, :id).to_a
    else
      []
    end
    @rows = selected.map do |shot|
      index = positions.fetch(shot.id)
      previous = index.positive? ? history[index - 1] : nil
      build_row(shot, index + 1, previous, history[index + 1], readings)
    end
    @compared_rows = rows.select { |row| row[:comparable] }
    @open_count = rows.count { |row| row[:status] == :open }
    @mean_change = mean(compared_rows.map { |row| row[:change] })
    paired = rows.select { |row| !row[:change].nil? }
    @first_reading = paired.map { |row| row[:baseline] }.min_by(&:recorded_at)
    @last_reading = paired.map { |row| row[:followup] }.max_by(&:recorded_at)
    @overall_change = first_reading && last_reading ? last_reading.in_unit(unit) - first_reading.in_unit(unit) : nil
    @locations = SITES.to_h do |name|
      matches = rows.select { |row| row[:site] == name }
      [name, { count: matches.length, sides: SIDES.to_h { |value| [value, matches.count { |row| row[:side] == value }] } }]
    end
    @site_groups = groups(rows.group_by { |row| grouping == "site" ? row[:site] : "#{row[:site]} · #{row[:side]}" }).sort_by do |group|
      place, direction = group[:label].split(" · ")
      [SITES.index(place) || 3, SIDES.index(direction) || 0]
    end
    @dose_groups = groups(rows.group_by { |row| "#{row[:injection].dose.to_s('F')} mg" }).sort_by { |group| group[:label].to_f }
  end

  def filter_params
    { range: range.range, from: range.from, to: range.to, site: site, side: side,
      dose: dose&.to_s("F") || "all", grouping: grouping }
  end

  def overall_percent = overall_change && overall_change / first_reading.in_unit(unit) * 100
  def mean_percent = mean(compared_rows.map { |row| row[:percent] })

  def chart
    {
      unit: unit, zone: @user.time_zone,
      history: Time.use_zone(@zone) { range.chart.slice(:from, :to, :raw, :days) }.merge(injections: rows.map { |row| chart_row(row).merge(x: row[:injection].recorded_at.to_f * 1000) }),
      shots: rows.last(24).map { |row| chart_row(row) },
      trajectories: rows.select { |row| !row[:change].nil? }.last(12).map do |row|
        chart_row(row).merge(points: ([row[:baseline]] + row[:readings]).map do |weight|
          { x: (weight.recorded_at - row[:injection].recorded_at) / 1.day,
            y: weight.in_unit(unit) - row[:baseline].in_unit(unit),
            value: weight.in_unit(unit), at: weight.recorded_at.iso8601 }
        end)
      end,
      sites: site_groups, doses: dose_groups
    }
  end

  private

  def build_row(shot, number, previous, following, readings)
    start = shot.recorded_at.in_time_zone(@zone)
    scheduled_end = start + FOLLOWUP_DAYS.days
    boundary = [scheduled_end, following&.recorded_at].compact.min
    effective_end = [boundary, @now].min
    future = shot.recorded_at > @now
    baseline = readings.reverse.find { |weight| weight.recorded_at <= shot.recorded_at && weight.recorded_at >= start - BASELINE_DAYS.days } unless future
    after = future ? [] : readings.select { |weight| weight.recorded_at > shot.recorded_at && weight.recorded_at <= effective_end }
    followup = after.last
    change = baseline && followup ? followup.in_unit(unit) - baseline.in_unit(unit) : nil
    span = baseline && followup ? (followup.recorded_at - baseline.recorded_at) / 1.day : nil
    complete = boundary <= @now
    status = if future then :future
    elsif !baseline then :no_baseline
    elsif !followup then :no_followup
    elsif !complete then :open
    elsif span < 1 then :short
    else :complete
    end
    {
      injection: shot, number: number, previous: previous, following: following,
      site: shot.site.presence || "Not recorded", side: shot.side.presence || "Not recorded",
      baseline: baseline, followup: followup, readings: after, change: change,
      percent: change && change / baseline.in_unit(unit) * 100,
      span_days: span, boundary: boundary, effective_end: effective_end,
      ended_by_next: following && following.recorded_at <= scheduled_end,
      interval_days: previous && (shot.recorded_at - previous.recorded_at) / 1.day,
      complete: complete, comparable: status == :complete, status: status
    }
  end

  def chart_row(row)
    shot = row[:injection]
    { id: shot.id, number: row[:number], day: shot.recorded_at.in_time_zone(@zone).to_date.iso8601,
      at: shot.recorded_at.iso8601, dose: shot.dose.to_s("F"), site: row[:site], side: row[:side],
      change: row[:change], percent: row[:percent], status: row[:status], span: row[:span_days] }
  end

  def groups(grouped)
    grouped.map do |label, shots|
      compared = shots.select { |row| row[:comparable] }
      { label: label, shots: shots.length, compared: compared.length,
        change: mean(compared.map { |row| row[:change] }),
        span: mean(compared.map { |row| row[:span_days] }) }
    end
  end

  def mean(values) = values.any? ? values.sum / values.length : nil
end
