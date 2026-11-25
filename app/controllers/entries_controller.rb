class EntriesController < ApplicationController
  before_action :set_kind
  before_action :set_calendar_date, only: [:new, :create]
  before_action :load_entry, only: [:edit, :update, :destroy]
  def new
    @entry = scope.new(uuid: SecureRandom.uuid, occurred_at: default_time.iso8601)
    @entry.unit = current_user.preferred_unit if @kind == "weight"
    @previous = current_user.injections.order(recorded_at: :desc).first
  end
  def edit
    @previous = current_user.injections.where.not(id: @entry.id).order(recorded_at: :desc).first
  end
  def create
    @entry = scope.find_by(uuid: params[:entry][:id])
    return saved_response("Entry already saved.") if @entry
    @entry = scope.new(entry_attributes.merge(uuid: params[:entry][:id]))
    save_entry(:new)
  rescue ActiveRecord::RecordNotUnique
    saved_response("Entry already saved.")
  rescue ArgumentError => e
    invalid_timestamp(e, :new)
  end
  def update
    @entry.assign_attributes(entry_attributes)
    save_entry(:edit)
  rescue ArgumentError => e
    invalid_timestamp(e, :edit)
  end
  def destroy
    @entry.destroy!
    redirect_to root_path, notice: "Entry deleted.", status: :see_other
  end
  private
  def set_kind
    @kind = params[:kind] == "injection" ? "injection" : "weight"
  end
  # Set when logging from a calendar day: prefills the date and returns there.
  def set_calendar_date
    @calendar_date = Date.iso8601(params[:date]) if params[:date].is_a?(String) && params[:date].present?
  rescue Date::Error
    @calendar_date = nil
  end
  def default_time
    return Time.current if @calendar_date.nil? || @calendar_date == Time.zone.today
    @calendar_date.in_time_zone.change(hour: 12)
  end
  def scope = @kind == "weight" ? current_user.weights : current_user.injections
  def load_entry = @entry = scope.find(params[:id])
  def entry_attributes
    fields = @kind == "weight" ? [:value, :unit] : [:dose, :site, :side, :notes]
    attrs = params.require(:entry).permit(*fields).to_h
    if @entry&.persisted? && params[:entry][:local_time] == @entry.recorded_at.in_time_zone.strftime("%Y-%m-%dT%H:%M") && params[:entry][:utc_offset].blank?
      attrs["occurred_at"] = @entry.occurred_at
    else
      attrs["occurred_at"] = local_timestamp(params[:entry][:local_time], params[:entry][:utc_offset])
    end
    attrs
  end
  def save_entry(template)
    if @entry.save
      current_user.update!(preferred_unit: @entry.unit) if @kind == "weight"
      saved_response("#{@kind.capitalize} saved.")
    else
      @previous = current_user.injections.order(recorded_at: :desc).first
      invalid_response(template)
    end
  end
  def invalid_timestamp(error, template)
    @entry ||= scope.new(params.require(:entry).permit(:value, :unit, :dose, :site, :side, :notes).to_h.merge(uuid: params[:entry][:id]))
    @entry.errors.add(:base, "Date and time are invalid. #{error.message}")
    @previous = current_user.injections.order(recorded_at: :desc).first
    invalid_response(template)
  end
  def saved_response(message)
    path = @calendar_date ? calendar_path(month: @entry.local_day.strftime("%Y-%m")) : root_path
    if request.format.json?
      flash[:notice] = message
      render json: { redirect_to: path }
    else
      redirect_to path, notice: message, status: :see_other
    end
  end
  def invalid_response(template)
    if request.format.json?
      render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
    else
      render template, status: :unprocessable_entity
    end
  end
end
