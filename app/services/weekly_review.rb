class WeeklyReview
  attr_reader :reading_before, :reading_after
  attr_reader :from, :to, :through, :current, :previous, :unit, :metric_summaries, :average, :previous_average, :change, :average_change_percent, :within_week_percent

  def initialize(user, week = nil)
    @unit = user.preferred_unit
    @from = (week.present? ? Date.iso8601(week) : Time.zone.today).beginning_of_week
    raise ArgumentError, "Choose this week or an earlier week" if from > Time.zone.today.beginning_of_week
    @to = from + 6
    @through = [to, Time.zone.today].min
    @current = Timeline.new(user, range: "custom", from: from.iso8601, to: through.iso8601)
    @previous = Timeline.new(user, range: "custom", from: (from - 7).iso8601, to: (from - 1).iso8601)
    # The nearest readings outside the week, however far away, let the chart
    # estimate its edges across gaps in logging.
    week_start, week_end = from.in_time_zone, (to + 1).in_time_zone
    @reading_before = user.weights.where(recorded_at: ...week_start).order(recorded_at: :desc).first
    # The current week never extends past the latest reading: nothing after today counts.
    @reading_after = user.weights.where(recorded_at: week_end..Time.current).order(:recorded_at).first unless through < to
    @average = mean(current.weights.map { |weight| weight.in_unit(unit) })
    @previous_average = mean(previous.weights.map { |weight| weight.in_unit(unit) })
    @change = average && previous_average ? average - previous_average : nil
    @average_change_percent = change && change / previous_average * 100
    @within_week_percent = if current.weights.size >= 2
      (current.weights.last.in_unit(unit) - current.weights.first.in_unit(unit)) / current.weights.first.in_unit(unit) * 100
    end
    @metric_summaries = MetricDefinitions::ALL.filter_map do |key, definition|
      next if definition["unit"] == "text"
      entries = current.notes.select { |note| note.metrics[key].present? }
      next if entries.empty?
      { key: key, label: definition["label"], unit: definition["unit"], count: entries.size,
        average: mean(entries.map { |note| note.metrics[key].to_f }) }
    end
  end

  def weighed_days = current.weights.map(&:local_day).uniq.length
  def journal_days = current.notes.length
  def partial? = through < to
  def plot = WeightPlot.new(current, unit, display_to: to, before: reading_before, after: reading_after)
  private
  def mean(values) = values.any? ? values.sum / values.length : nil
end
