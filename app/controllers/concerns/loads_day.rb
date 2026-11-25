# One local day's records, shared by the journal page and the calendar's day dialog.
module LoadsDay
  extend ActiveSupport::Concern
  private
  def load_day
    @date = Date.iso8601(params[:date])
    day = @date.in_time_zone...(@date + 1).in_time_zone
    @note = current_user.day_notes.find_or_initialize_by(local_date: @date)
    @weights = current_user.weights.where(recorded_at: day).order(:recorded_at)
    @injections = current_user.injections.where(recorded_at: day).order(:recorded_at)
  rescue Date::Error
    raise ActionController::BadRequest, "Invalid calendar date"
  end
end
