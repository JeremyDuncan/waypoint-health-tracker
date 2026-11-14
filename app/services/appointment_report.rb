class AppointmentReport
  attr_reader :range, :unit, :include_notes, :include_metrics, :metrics, :plot
  def initialize(user, options = {})
    @unit = user.preferred_unit
    @include_notes = options[:include_notes] == "1"
    @include_metrics = options[:include_metrics] != "0"
    @range = Timeline.new(user, options.slice(:range, :from, :to).merge(range: options[:range].presence || "90"))
    raise ArgumentError, "Choose at most one year for an appointment report" if (range.to - range.from).to_i > 366
    @plot = WeightPlot.new(range, unit)
    @metrics = if include_metrics
      range.notes.select { |note| note.metrics.present? }
    else
      []
    end
  end

  def weight_change
    range.weights.size >= 2 ? range.weights.last.in_unit(unit) - range.weights.first.in_unit(unit) : nil
  end
  def weight_change_percent = weight_change && weight_change / range.weights.first.in_unit(unit) * 100
end
