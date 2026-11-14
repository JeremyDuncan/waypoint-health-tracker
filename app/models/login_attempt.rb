class LoginAttempt < ApplicationRecord
  # Persist throttles in SQLite so container restarts do not reset them.
  def self.allowed?(key)
    transaction do
      attempt = find_or_create_by!(key: key) { |a| a.window_started_at = Time.current }
      attempt.with_lock do
        if attempt.window_started_at < 15.minutes.ago
          attempt.update!(count: 0, window_started_at: Time.current)
        end
        return false if attempt.count >= 10
        attempt.increment!(:count)
      end
    end
    true
  end
end
