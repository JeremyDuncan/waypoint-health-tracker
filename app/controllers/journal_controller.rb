class JournalController < ApplicationController
  include LoadsDay
  before_action :load_day
  def show; end
  def update
    attrs = params.require(:day_note).permit(:notes, metrics: MetricDefinitions::ALL.keys).to_h
    attrs["metrics"] = (attrs["metrics"] || {}).reject { |_, v| v.blank? }
    @note.assign_attributes(attrs)
    if @note.save
      if request.format.json?
        flash[:notice] = "Journal saved."
        render json: { redirect_to: saved_path }
      else
        redirect_to saved_path, notice: "Journal saved.", status: :see_other
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
  def saved_path = params[:return_to] == "calendar" ? calendar_path(month: @date.strftime("%Y-%m")) : journal_path(@date)
end
