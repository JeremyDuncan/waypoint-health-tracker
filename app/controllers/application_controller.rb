class ApplicationController < ActionController::Base
  include Authentication
  before_action :private_response
  around_action :use_personal_time_zone
  helper_method :current_user
  private
  def current_user = Current.user
  def private_response
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["Vary"] = "Cookie"
    response.headers["Referrer-Policy"] = "same-origin"
  end
  def use_personal_time_zone(&block)
    Time.use_zone(current_user&.time_zone || "UTC", &block)
  end
  def local_timestamp(input, explicit_offset = nil)
    raise ArgumentError, "Choose a valid local date and time" unless input.to_s.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)
    Date.iso8601(input[0, 10])
    parts = DateTime.strptime(input, "%Y-%m-%dT%H:%M")
    local = Time.utc(parts.year, parts.month, parts.day, parts.hour, parts.minute)
    periods = Time.zone.tzinfo.periods_for_local(local)
    raise ArgumentError, "This time does not exist because clocks moved forward" if periods.empty?
    if explicit_offset.present?
      raise ArgumentError, "Use an offset such as -04:00 or -05:00" unless explicit_offset.match?(/\A[+-]\d{2}:\d{2}\z/)
      selected = Time.iso8601("#{input}:00#{explicit_offset}")
      raise ArgumentError, "Offset does not match your time zone at this time" unless periods.any? { |p| p.observed_utc_offset == selected.utc_offset }
      return selected.iso8601
    end
    raise ArgumentError, "This time occurs twice because clocks moved back. Open Clock change and choose the actual UTC offset." if periods.size > 1
    Time.zone.strptime(input, "%Y-%m-%dT%H:%M").iso8601
  end
end
