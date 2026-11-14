class DashboardController < ApplicationController
  def index
    @chart_preferences = ChartPreferences.for(current_user, "overview", params.permit(*ChartPreferences.keys("overview")).to_h)
    @range = Timeline.new(current_user, @chart_preferences.symbolize_keys)
    @filter_values = @chart_preferences.merge("from" => @range.from, "to" => @range.to)
    load_summary
  rescue ArgumentError, Date::Error => e
    flash.now[:alert] = e.message
    @chart_preferences = ChartPreferences.for(current_user, "overview")
    @range = Timeline.new(current_user, @chart_preferences.symbolize_keys)
    @filter_values = @chart_preferences.merge("from" => @range.from, "to" => @range.to).merge(params.permit(*ChartPreferences.keys("overview")).to_h)
    @filter_error = true
    load_summary
    render :index, status: :unprocessable_entity
  end
  private
  def load_summary
    @latest = current_user.weights.order(recorded_at: :desc).first
    @range_first = @range.weights.first
    @range_last = @range.weights.last
    @range_change = if @range.weights.size >= 2
      @range_last.in_unit(current_user.preferred_unit) - @range_first.in_unit(current_user.preferred_unit)
    end
    @range_change_percent = @range_change && @range_change / @range_first.in_unit(current_user.preferred_unit) * 100
    @last_injection = current_user.injections.order(recorded_at: :desc).first
  end
end
