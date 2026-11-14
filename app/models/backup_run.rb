class BackupRun < ApplicationRecord
  validates :status, inclusion: { in: %w[running succeeded failed] }

  def available?
    status == "succeeded" && File.file?(destination) && File.size(destination) == byte_size
  rescue SystemCallError
    false
  end

  def interrupted? = status == "running" && started_at < 15.minutes.ago
end
