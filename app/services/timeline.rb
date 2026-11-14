class Timeline
  attr_reader :from, :to, :range, :weights, :injections, :notes, :events
  def initialize(user, options)
    @user = user
    @range = options[:range].presence || "30"
    @to = Time.zone.today
    @from = case @range
    when "7", "30", "90", "365" then @to - (@range.to_i - 1)
    when "all"
      [user.weights.minimum(:recorded_at)&.in_time_zone&.to_date,
       user.injections.minimum(:recorded_at)&.in_time_zone&.to_date, user.day_notes.minimum(:local_date), @to].compact.min
    when "custom"
      @to = Date.iso8601(options[:to].to_s)
      Date.iso8601(options[:from].to_s)
    else raise ArgumentError, "Choose a valid date range"
    end
    raise ArgumentError, "Start date must be before the end date" if @from > @to
    raise ArgumentError, "Choose a range of at most 100 years" if (@to - @from).to_i > 36600
    interval = @from.in_time_zone...(@to + 1).in_time_zone
    @weights = user.weights.where(recorded_at: interval).order(:recorded_at).to_a
    @injections = user.injections.where(recorded_at: interval).order(:recorded_at).to_a
    @notes = user.day_notes.where(local_date: @from..@to).order(:local_date).to_a
    @events = (weights + injections + notes).sort_by { |e| e.is_a?(DayNote) ? e.local_date.in_time_zone : e.recorded_at }
  end
  def chart
    raw = weights.map { |w| { x: w.recorded_at.to_f * 1000, y: w.in_unit(@user.preferred_unit), day: w.local_day.iso8601, id: w.id } }
    weekly = averages_by { |w| w.local_day.beginning_of_week }
    monthly = averages_by { |w| w.local_day.beginning_of_month }
    { from: from.in_time_zone.to_f * 1000, to: (to + 1).in_time_zone.to_f * 1000 - 1,
      zone: @user.time_zone, unit: @user.preferred_unit, raw: raw, weekly: weekly, monthly: monthly, trend: rolling_trend,
      days: (to - from).to_i < 31 ? (from..to).map { |day| { day: day.iso8601, start: day.in_time_zone.to_f * 1000, finish: (day + 1).in_time_zone.to_f * 1000, noon: day.in_time_zone.change(hour: 12).to_f * 1000, weekend: day.saturday? || day.sunday? } } : [],
      injections: injections.map { |i| { x: i.recorded_at.to_f * 1000, day: i.local_day.iso8601, label: "#{i.dose.to_s('F')} mg", site: i.site, side: i.side } },
      notes: notes.map { |n| { x: n.local_date.in_time_zone.change(hour: 12).to_f * 1000, day: n.local_date.iso8601, label: "Journal" } } }
  end

  private

  def rolling_trend
    return [] if weights.empty?
    context = @user.weights.where(recorded_at: (weights.first.recorded_at - 7.days)..weights.last.recorded_at).order(:recorded_at, :id).to_a
    left = right = 0
    sum = 0.0
    weights.map do |weight|
      while right < context.size && context[right].recorded_at <= weight.recorded_at
        sum += context[right].in_unit(@user.preferred_unit)
        right += 1
      end
      while left < right && context[left].recorded_at <= weight.recorded_at - 7.days
        sum -= context[left].in_unit(@user.preferred_unit)
        left += 1
      end
      { x: weight.recorded_at.to_f * 1000, y: sum / (right - left), day: weight.local_day.iso8601, count: right - left }
    end
  end

  def averages_by(&period)
    weights.group_by(&period).map do |_, readings|
      last = readings.last
      { x: last.recorded_at.to_f * 1000, y: readings.sum { |w| w.in_unit(@user.preferred_unit) } / readings.size,
        day: last.local_day.iso8601, count: readings.size }
    end
  end
end
