class ImportsController < ApplicationController
  before_action :load_batch, except: [:create]
  def create
    upload = params[:file]
    raise ArgumentError, "Choose a UTF-8 CSV or JSON file (maximum 5 MB)." unless upload && upload.size <= 5.megabytes
    text = upload.read.force_encoding("UTF-8").delete_prefix("\uFEFF")
    raise ArgumentError, "File is not valid UTF-8" unless text.valid_encoding?
    current_user.import_batches.where("created_at < ?", 1.hour.ago).delete_all
    payload = if params[:format_kind] == "json"
      PersonalImport.parse_json(text)
    elsif params[:format_kind] == "renpho" || RenphoCsv.detect?(CSV.parse_line(text))
      RenphoCsv.parse(text, time_zone: current_user.time_zone).merge("csv" => text)
    else
      { "csv" => text }
    end
    @batch = current_user.import_batches.create!(payload: payload)
    redirect_to import_path(@batch), status: :see_other
  rescue ArgumentError, JSON::ParserError, CSV::MalformedCSVError => e
    redirect_to settings_path, alert: e.message, status: :see_other
  end
  def show
    @renpho = @batch.payload["source_format"] == "renpho"
    @mapping = @batch.payload["mapping"] || {}
    if @batch.payload["csv"]
      @headers = CSV.parse(@batch.payload["csv"], headers: true).headers
    end
    @report = PersonalImport.new(current_user, @batch.payload).report if @batch.payload["records"]
  end
  def preview
    payload = if @batch.payload["source_format"] == "renpho"
      RenphoCsv.parse(@batch.payload.fetch("csv"), time_zone: params[:time_zone].presence || @batch.payload["time_zone"])
    else
      mapping = params.permit(:date_column, :value_column, :unit_column, :id_column, :unit, :date_format, :offset).to_h
      PersonalImport.parse_csv(@batch.payload.fetch("csv"), mapping).merge("mapping" => mapping)
    end
    @batch.update!(payload: payload.merge("csv" => @batch.payload["csv"]))
    redirect_to import_path(@batch), status: :see_other
  rescue ArgumentError, CSV::MalformedCSVError => e
    redirect_to import_path(@batch), alert: e.message, status: :see_other
  end
  def commit
    raise ArgumentError, "Preview and validate the file first" unless @batch.payload["records"]
    report = PersonalImport.new(current_user, @batch.payload).commit!(@batch, apply_preferences: params[:apply_preferences] == "1")
    redirect_to settings_path, notice: import_notice(report), status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    redirect_to import_path(@batch), alert: e.message, status: :see_other
  end
  private
  def import_notice(report)
    return "This file was already imported." unless report
    imported = helpers.pluralize(report["creates"], "new entry", plural: "new entries")
    skipped = helpers.pluralize(report["duplicates"], "duplicate")
    "Imported #{imported}. Skipped #{skipped}."
  end
  def load_batch
    @batch = current_user.import_batches.find(params[:id])
    raise ActiveRecord::RecordNotFound if @batch.expired?
  end
end
