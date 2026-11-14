class ReportsController < ApplicationController
  def show
    @report = AppointmentReport.new(current_user, params.permit(:range, :from, :to, :include_notes, :include_metrics).to_h.symbolize_keys)
    if request.format.pdf?
      send_data AppointmentPdf.new(@report, current_user.time_zone).render,
        type: "application/pdf", filename: "waypoint-health-appointment-#{@report.range.from}-#{@report.range.to}.pdf", disposition: "attachment"
    end
  rescue ArgumentError, Date::Error => error
    flash.now[:alert] = error.message
    @report = AppointmentReport.new(current_user)
    render :show, formats: [:html], status: :unprocessable_entity
  end
end
