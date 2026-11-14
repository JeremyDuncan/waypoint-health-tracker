class ChartPreferences
  DEFAULTS = {
    "overview" => { "range" => "30", "mode" => "raw", "trend" => false, "weight" => true, "injections" => true, "notes" => true },
    "injections" => { "range" => "90", "mode" => "calendar", "site" => "all", "side" => "all", "dose" => "all", "grouping" => "site_side" }
  }.freeze
  RANGES = %w[7 30 90 365 all custom].freeze

  def self.keys(page) = DEFAULTS.fetch(page).keys + %w[from to]

  def self.for(user, page, overrides = {})
    normalize(page, (user.chart_preferences[page] || {}).merge(overrides.stringify_keys))
  end

  def self.normalize(page, input)
    raise ArgumentError, "Unsupported chart settings" unless input.is_a?(Hash) && (input.keys - keys(page)).empty?
    state = DEFAULTS.fetch(page).merge(input)
    raise ArgumentError, "Choose a valid date range" unless RANGES.include?(state["range"])
    if state["range"] == "custom"
      from, to = %w[from to].map do |key|
        text = state[key].to_s
        raise ArgumentError, "Choose valid custom dates" unless text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        Date.iso8601(text)
      end
      raise ArgumentError, "Start date must be before the end date" if from > to
      raise ArgumentError, "Choose a range of at most 100 years" if (to - from).to_i > 36600
      state.merge!("from" => from.iso8601, "to" => to.iso8601)
    else
      state.except!("from", "to")
    end
    if page == "overview"
      raise ArgumentError, "Choose a listed chart view" unless %w[raw weekly monthly].include?(state["mode"])
      %w[trend weight injections notes].each do |key|
        raise ArgumentError, "Choose valid chart visibility settings" unless [true, false, "0", "1", "true", "false"].include?(state[key])
        state[key] = [true, "1", "true"].include?(state[key])
      end
    else
      raise ArgumentError, "Choose a listed chart view" unless %w[calendar aligned].include?(state["mode"])
      raise ArgumentError, "Choose a listed injection site" unless %w[all unknown Abdomen Thigh].include?(state["site"]) || state["site"] == "Upper arm"
      raise ArgumentError, "Choose a listed injection side" unless %w[all unknown Left Right].include?(state["side"])
      raise ArgumentError, "Choose a listed location comparison" unless %w[site site_side].include?(state["grouping"])
      unless state["dose"] == "all"
        dose = BigDecimal(state["dose"].to_s, exception: false)
        raise ArgumentError, "Choose a listed dose" unless InjectionInsights::DOSES.include?(dose)
        state["dose"] = dose.to_s("F")
      end
    end
    state
  end

  def self.validate_document!(document)
    raise ArgumentError, "must contain only Overview and Injections settings" unless document.is_a?(Hash) && (document.keys - DEFAULTS.keys).empty?
    document.each do |page, state|
      raise ArgumentError, "must contain complete, valid chart settings" unless normalize(page, state) == state
    end
  end
end
