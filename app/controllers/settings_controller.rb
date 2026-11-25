class SettingsController < ApplicationController
  before_action :load_backup_status, only: [:show, :update, :change_password, :clear_history]
  def show; end
  def update
    attrs = params.require(:user).permit(:preferred_unit, :time_zone, :reminder_local, enabled_metrics: []).to_h
    attrs["enabled_metrics"] ||= []
    reminder = attrs.delete("reminder_local")
    if reminder.present?
      zone = ActiveSupport::TimeZone[attrs["time_zone"] || current_user.time_zone]
      raise ArgumentError unless zone
      attrs["reminder_at"] = zone.strptime(reminder, "%Y-%m-%dT%H:%M")
    else
      attrs["reminder_at"] = nil
    end
    if current_user.update(attrs)
      redirect_to settings_path, notice: "Preferences saved.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  rescue ArgumentError
    current_user.errors.add(:base, "Reminder date or time zone is invalid")
    render :show, status: :unprocessable_entity
  end
  def change_password
    @password_change = true
    attrs = params.require(:user).permit(:current_password, :password, :password_confirmation)
    # Rails checks password_challenge against the persisted digest. Always supply
    # strings so omitted fields cannot bypass challenge/confirmation validation.
    changed = current_user.with_lock do
      current_user.assign_attributes(password_challenge: attrs[:current_password].to_s,
        password: attrs[:password].to_s, password_confirmation: attrs[:password_confirmation].to_s)
      if current_user.save(context: :password_change)
        current_user.sessions.destroy_all
        true
      end
    end
    if changed
      terminate_session
      redirect_to new_session_path, notice: "Password changed. Sign in again on each device.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end
  def clear_history
    if params[:confirmation].to_s.strip == User::CLEAR_HISTORY_PHRASE
      current_user.clear_health_history!
      redirect_to settings_path, notice: "Health history cleared.", status: :see_other
    else
      @history_error = "Nothing was deleted. Type #{User::CLEAR_HISTORY_PHRASE} exactly to confirm."
      render :show, status: :unprocessable_entity
    end
  end
  def export
    exporter = PersonalExport.new(current_user)
    if params[:kind] == "json"
      send_data JSON.pretty_generate(exporter.document), filename: "waypoint-health-personal-v1.json", type: "application/json; charset=utf-8"
    elsif PersonalExport::FIELDS.key?(params[:kind])
      send_data exporter.csv(params[:kind]), filename: "waypoint-health-#{params[:kind]}.csv", type: "text/csv; charset=utf-8"
    else
      head :not_found
    end
  end
  private
  def load_backup_status
    @last_backup = BackupRun.where(status: "succeeded").order(completed_at: :desc).first
    @backup_attempt = BackupRun.order(started_at: :desc, id: :desc).first
  end
end
