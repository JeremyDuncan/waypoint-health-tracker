class GoalsController < ApplicationController
  def show
    @progress = GoalProgress.new(current_user)
    @goal = WeightGoalConfig.new(current_user.weight_goal || { mode: "target", unit: current_user.preferred_unit, start_date: Time.zone.today.iso8601 })
    @height_value = current_user.height_cm&.to_s("F")
    @height_unit = "cm"
  end

  def update
    @goal = WeightGoalConfig.new(params.require(:goal).permit(*WeightGoalConfig::FIELDS).to_h)
    valid = @goal.valid?
    attributes = {}
    @height_value, @height_unit = params[:height_value], params[:height_unit].presence || "cm"
    if params.key?(:height_value)
      height = BigDecimal(@height_value.to_s, exception: false)
      if @height_value.blank?
        attributes[:height_cm] = nil
      elsif !%w[cm in].include?(@height_unit) || !height&.finite? || height <= 0 || (height * (@height_unit == "in" ? BigDecimal("2.54") : 1)) > 300
        @goal.errors.add(:base, "Height must be a positive number up to 300 cm (118.11 in)")
        valid = false
      else
        attributes[:height_cm] = (height * (@height_unit == "in" ? BigDecimal("2.54") : 1)).round(4)
      end
    else
      @height_value = current_user.height_cm&.to_s("F")
    end
    if valid && current_user.update(attributes.merge(weight_goal: @goal.portable))
      redirect_to goal_path, notice: "Weight goal saved.", status: :see_other
    else
      @progress = GoalProgress.new(current_user)
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    current_user.update!(weight_goal: nil)
    redirect_to goal_path, notice: "Goal cleared. Your weigh-ins are kept.", status: :see_other
  end
end
