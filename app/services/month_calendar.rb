class MonthCalendar
  attr_reader :month, :today, :weeks, :weight_count, :injection_count, :journal_count

  def initialize(user, selected_month = nil)
    zone = Time.find_zone!(user.time_zone)
    @today = zone.today
    @month = if selected_month.present?
      raise ArgumentError, "Choose a calendar month in YYYY-MM format" unless selected_month.to_s.match?(/\A(?!0000)\d{4}-(?:0[1-9]|1[0-2])\z/)
      Date.strptime(selected_month, "%Y-%m")
    else
      today.beginning_of_month
    end

    @days = Hash.new { |days, date| days[date] = { weights: 0, injections: 0, doses: [], journal: nil } }
    interval = month.in_time_zone(zone)...month.next_month.in_time_zone(zone)
    weights = user.weights.where(recorded_at: interval).pluck(:recorded_at)
    injections = user.injections.where(recorded_at: interval).order(:recorded_at).pluck(:recorded_at, :dose)
    weights.each { |time| @days[time.in_time_zone(zone).to_date][:weights] += 1 }
    injections.each do |time, dose|
      day = @days[time.in_time_zone(zone).to_date]
      day[:injections] += 1
      day[:doses] << dose
    end
    @weight_count, @injection_count = weights.length, injections.length

    @journal_count = 0
    user.day_notes.where(local_date: month..month.end_of_month).each do |note|
      next if note.notes.blank? && note.metrics.blank?
      @days[note.local_date][:journal] = note
      @journal_count += 1
    end
    @weeks = (month.beginning_of_week(:monday)..month.end_of_month.end_of_week(:monday)).each_slice(7).to_a
  end

  def events_on(date) = @days[date]
  def includes?(date) = date >= month && date <= month.end_of_month
  def empty? = weight_count.zero? && injection_count.zero? && journal_count.zero?

  def day_label(date)
    events = events_on(date)
    entries = []
    entries << "#{events[:weights]} #{events[:weights] == 1 ? 'weigh-in' : 'weigh-ins'}" if events[:weights] > 0
    entries << "#{events[:injections]} #{events[:injections] == 1 ? 'injection' : 'injections'} (#{events[:doses].uniq.map { |dose| "#{dose.to_s('F')} mg" }.join(', ')})" if events[:injections] > 0
    entries << (events[:journal].notes.present? ? "journal note" : "journal metrics") if events[:journal]
    "#{date.strftime('%A, %B %-d, %Y')}: #{entries.presence&.join(', ') || 'no entries yet'}. Add or view entries."
  end
end
