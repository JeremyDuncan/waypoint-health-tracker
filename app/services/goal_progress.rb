class GoalProgress
  attr_reader :config, :weights, :baseline, :latest, :current, :milestones, :percent

  def initialize(user, now: Time.current)
    @user = user
    @config = user.weight_goal
    @current = user.weights.where(recorded_at: ..now).order(:recorded_at, :id).last
    @weights, @milestones = [], []
    return unless config
    start = Date.iso8601(config.fetch("start_date")).in_time_zone(user.time_zone)
    @weights = user.weights.where(recorded_at: start..now).order(:recorded_at, :id).to_a
    @baseline, @latest = weights.first, weights.last
    return unless baseline && config["mode"] == "target"
    first = baseline.in_unit(config["unit"])
    target = config.fetch("value").to_f
    difference = target - first
    @percent = difference.zero? ? (latest.in_unit(config["unit"]) == target ? 100.0 : 0.0) : ((latest.in_unit(config["unit"]) - first) / difference * 100).clamp(0, 100)
    @milestones = [25, 50, 75, 100].map do |portion|
      threshold = first + difference * portion / 100.0
      reached = weights.find { |weight| difference.positive? ? weight.in_unit(config["unit"]) >= threshold : weight.in_unit(config["unit"]) <= threshold }
      { percent: portion, value: threshold, reached: reached }
    end
  end

  def maintenance? = config && config["mode"] == "maintenance"
  def bmi = current && @user.height_cm&.positive? ? current.in_unit("kg") / (@user.height_cm.to_f / 100)**2 : nil
  def change = baseline && latest ? latest.in_unit(@user.preferred_unit) - baseline.in_unit(@user.preferred_unit) : nil
  def change_percent = change && change / baseline.in_unit(@user.preferred_unit) * 100
  def remaining
    return unless latest && baseline && !maintenance?
    target = config["value"].to_f
    value = latest.in_unit(config["unit"])
    distance = target >= baseline.in_unit(config["unit"]) ? target - value : value - target
    [distance, 0].max * (config["unit"] == @user.preferred_unit ? 1 : config["unit"] == "lb" ? 0.45359237 : 1 / 0.45359237)
  end
  def in_range?(weight) = weight.in_unit(config["unit"]).between?(config["low"].to_f, config["high"].to_f)
  def measured_days = weights.map(&:local_day).uniq.length
  # Use the last actual reading on each day, so multiple measurements do not
  # turn one day into several maintenance achievements.
  def days_in_range = weights.group_by(&:local_day).count { |_, readings| in_range?(readings.last) }
end
