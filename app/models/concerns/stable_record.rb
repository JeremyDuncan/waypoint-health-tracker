module StableRecord
  extend ActiveSupport::Concern
  included do
    before_validation do
      self.uuid ||= SecureRandom.uuid
      self.uuid = uuid.downcase if uuid.is_a?(String)
    end
    validates :uuid, format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i }
  end
end
