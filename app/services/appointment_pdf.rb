require "prawn"

class AppointmentPdf
  def initialize(report, zone)
    @report, @zone = report, zone
  end

  def render
    @pdf = Prawn::Document.new(page_size: "A4", margin: [42, 40, 48, 40], info: { Title: "Waypoint Health appointment report", Creator: "Waypoint Health" })
    fonts = Rails.root.join("vendor/fonts")
    @pdf.font_families.update("Noto" => { normal: fonts.join("NotoSans-Regular.ttf").to_s, bold: fonts.join("NotoSans-Bold.ttf").to_s },
      "Symbols" => { normal: fonts.join("NotoSansSymbols2-Regular.ttf").to_s },
      "Emoji" => { normal: fonts.join("NotoEmoji.ttf").to_s })
    @pdf.font("Noto", size: 9)
    @pdf.fallback_fonts = ["Symbols", "Emoji"]
    @pdf.fill_color "214F40"
    @pdf.text "Waypoint Health / appointment report", size: 22, style: :bold
    @pdf.move_down 8
    line "#{@report.range.from} through #{@report.range.to} · #{@zone}"
    line "Generated #{Time.current.in_time_zone(@zone).strftime('%b %-d, %Y %H:%M %Z')}. Actual personal logs; missing measurements are not estimated."
    @pdf.move_down 12
    title "Weight overview"
    readings = @report.range.weights
    if readings.any?
      line "#{readings.size} weigh-ins · first #{number(readings.first.in_unit(@report.unit))} #{@report.unit} · last #{number(readings.last.in_unit(@report.unit))} #{@report.unit}"
      line "Observed change: #{@report.weight_change ? number(@report.weight_change) + ' ' + @report.unit : 'Needs two readings'}"
      percentage = @report.weight_change_percent
      line "Percentage: #{number(percentage.abs)}% #{percentage < 0 ? 'lost' : percentage > 0 ? 'gained' : 'change'} from the first selected reading" if percentage
    else
      line "No weigh-ins in this range."
    end
    plot
    title "Actual injections (#{@report.range.injections.size})"
    @report.range.injections.each do |shot|
      line "#{timestamp(shot.recorded_at)} · #{shot.dose.to_s('F')} mg · #{[shot.site, shot.side].compact_blank.join(' / ').presence || 'Location not recorded'}", bold: true
      line shot.notes if @report.include_notes && shot.notes.present?
      @pdf.move_down 5
    end
    line "No actual injections in this range. Planned reminders are excluded." if @report.range.injections.empty?
    if @report.include_metrics
      title "Journal metrics"
      @report.metrics.each do |note|
        line note.local_date.iso8601, bold: true
        note.metrics.each { |key, value| line "#{MetricDefinitions::ALL.fetch(key)['label']}: #{MetricDefinitions.format_value(key, value)}" }
        @pdf.move_down 5
      end
      line "No journal metrics recorded in this range." if @report.metrics.empty?
    end
    if @report.include_notes
      title "Selected journal notes"
      @report.range.notes.select { |note| note.notes.present? }.each do |note|
        line note.local_date.iso8601, bold: true
        line note.notes
        @pdf.move_down 6
      end
    else
      line "Free-text journal and injection notes were excluded."
    end
    title "Exact weigh-ins"
    readings.each { |weight| line "#{timestamp(weight.recorded_at)} · #{weight.value.to_s('F')} #{weight.unit} (#{number(weight.in_unit(@report.unit))} #{@report.unit})" }
    @pdf.number_pages "Waypoint Health · Private personal report · <page> / <total>", at: [0, -25], size: 8, align: :center, color: "68766C"
    @pdf.render
  end

  private

  def line(text, bold: false)
    @pdf.fill_color "253E34"
    @pdf.text text.to_s, size: 9, style: bold ? :bold : :normal, leading: 3
    @pdf.move_down 3
  end

  def title(text)
    @pdf.start_new_page if @pdf.cursor < 85
    @pdf.move_down 10
    @pdf.fill_color "214F40"
    @pdf.text text, size: 13, style: :bold
    @pdf.move_down 8
  end

  def number(value) = format("%.2f", value)
  def timestamp(value) = value.in_time_zone(@zone).strftime("%Y-%m-%d %H:%M %:z")

  def plot
    @pdf.start_new_page if @pdf.cursor < 210
    data = @report.plot
    top = @pdf.cursor - 15
    left = 37
    width = @pdf.bounds.width - left - 5
    bottom = top - 130
    @pdf.stroke_color "D8DED5"
    @pdf.line_width 0.6
    @pdf.stroke_line [left, bottom], [left + width, bottom]
    @pdf.stroke_line [left, top], [left + width, top]
    if data.points.any?
      @pdf.fill_color "68766C"
      @pdf.draw_text number(data.maximum), at: [0, top - 3], size: 8
      @pdf.draw_text number(data.minimum), at: [0, bottom - 3], size: 8
      @pdf.stroke_color "287758"
      @pdf.line_width 1.5
      SmoothLine.segments(data.points).each do |segment|
        transform = ->(point) { [left + point[:x] * width, bottom + point[:y] * 130] }
        @pdf.stroke { @pdf.curve transform.call(segment[:from]), transform.call(segment[:to]), bounds: segment[:controls].map { |point| transform.call(point) } }
      end
      @pdf.fill_color "287758"
      data.points.each { |point| @pdf.fill_circle [left + point[:x] * width, bottom + point[:y] * 130], 2 }
    end
    @pdf.stroke_color "BB7C3C"
    @pdf.dash 3
    data.injections.each { |point| @pdf.stroke_line [left + point[:x] * width, bottom - 5], [left + point[:x] * width, top] }
    @pdf.undash
    @pdf.move_cursor_to bottom - 15
    line "Green: actual weights (#{@report.unit}). Orange guides: actual injection times; exact doses and locations are listed below."
  end
end
