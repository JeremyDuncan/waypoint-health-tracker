class JournalController < ApplicationController
  before_action :load_day
  def show; end
  def update
    attrs = params.require(:day_note).permit(:notes, metrics: MetricDefinitions::ALL.keys).to_h
    attrs["metrics"] = (attrs["metrics"] || {}).reject { |_, v| v.blank? }
    @note.assign_attributes(attrs)
    if @note.save
      if request.format.json?
        flash[:notice] = "Journal saved."
        render json: { redirect_to: journal_path(@date) }
      else
        redirect_to journal_path(@date), notice: "Journal saved.", status: :see_other
      end
    else
      if request.format.json?
        render json: { errors: @note.errors.full_messages }, status: :unprocessable_entity
      else
        render :show, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to journal_path(@date), alert: "This day was saved in another tab. Reload before editing.", status: :see_other
  end
  def destroy
    @note.destroy! if @note.persisted?
    redirect_to journal_path(@date), notice: "Journal cleared.", status: :see_other
  end
  private
  def load_day
    @date = Date.iso8601(params[:date])
    @note = current_user.day_notes.find_or_initialize_by(local_date: @date)
    @weights = current_user.weights.where(recorded_at: @date.in_time_zone...(@date + 1).in_time_zone).order(:recorded_at)
    @injections = current_user.injections.where(recorded_at: @date.in_time_zone...(@date + 1).in_time_zone).order(:recorded_at)
  rescue Date::Error
    raise ActionController::BadRequest, "Invalid calendar date"
  end
end
