class ImportBatch < ApplicationRecord
  before_validation { self.id ||= SecureRandom.uuid }
  belongs_to :user
  def expired? = created_at < 1.hour.ago
end
