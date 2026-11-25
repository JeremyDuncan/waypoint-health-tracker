class CalendarsController < ApplicationController
  include LoadsDay
  before_action :load_day, only: :day
  def day; end
  def show
    @calendar = MonthCalendar.new(current_user, params[:month])
  rescue ArgumentError, Date::Error => e
    flash.now[:alert] = e.message
    @calendar = MonthCalendar.new(current_user)
    render :show, status: :unprocessable_entity
  end
end
