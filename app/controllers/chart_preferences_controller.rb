class ChartPreferencesController < ApplicationController
  before_action :load_page

  def update
    input = params.require(:preferences).permit(*ChartPreferences.keys(@page)).to_h
    state = nil
    current_user.with_lock do
      state = ChartPreferences.for(current_user, @page, input)
      current_user.update!(chart_preferences: current_user.chart_preferences.merge(@page => state))
    end
    respond_to do |format|
      format.json { render json: { preferences: state } }
      format.html { redirect_to chart_path, notice: "Chart filters saved.", status: :see_other }
    end
  rescue ArgumentError, Date::Error => error
    respond_to do |format|
      format.json { render json: { error: error.message }, status: :unprocessable_entity }
      format.html { redirect_to chart_path(**input.symbolize_keys.merge(edit_filters: "1")), alert: error.message, status: :see_other }
    end
  end

  def destroy
    current_user.with_lock do
      current_user.update!(chart_preferences: current_user.chart_preferences.except(@page))
    end
    redirect_to chart_path, notice: "Chart filters and view reset to defaults.", status: :see_other
  end

  private
  def load_page
    @page = params[:page]
    head :not_found unless ChartPreferences::DEFAULTS.key?(@page)
  end
  def chart_path(**options) = @page == "overview" ? root_path(**options) : injections_path(**options)
end
