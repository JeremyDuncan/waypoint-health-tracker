class ReviewsController < ApplicationController
  def show
    @review = WeeklyReview.new(current_user, params[:week])
  rescue ArgumentError, Date::Error => error
    flash.now[:alert] = error.message
    @review = WeeklyReview.new(current_user)
    render :show, status: :unprocessable_entity
  end
end
