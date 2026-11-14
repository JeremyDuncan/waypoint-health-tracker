class InjectionsController < ApplicationController
  def index
    @chart_preferences = ChartPreferences.for(current_user, "injections", params.permit(*ChartPreferences.keys("injections")).to_h)
    @insights = InjectionInsights.new(current_user, @chart_preferences.symbolize_keys)
    @filter_values = @chart_preferences.merge("from" => @insights.range.from, "to" => @insights.range.to)
  rescue ArgumentError, Date::Error => e
    flash.now[:alert] = e.message
    @chart_preferences = ChartPreferences.for(current_user, "injections")
    @insights = InjectionInsights.new(current_user, @chart_preferences.symbolize_keys)
    @filter_values = @chart_preferences.merge("from" => @insights.range.from, "to" => @insights.range.to).merge(params.permit(*ChartPreferences.keys("injections")).to_h)
    @filter_error = true
    render :index, status: :unprocessable_entity
  end
end
