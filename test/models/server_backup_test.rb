require "test_helper"
require "tmpdir"
require "open3"

class ServerBackupTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "online backup tracks success and failures and restores accounts goals and records into a fresh database" do
    user = create_user("backup-check@example.test")
    user.update!(weight_goal: { mode: "target", value: "180", unit: "lb", start_date: "2026-01-01", low: nil, high: nil })
    user.weights.create!(value: 200, unit: "lb", occurred_at: "2026-01-01T08:00:00-05:00")
    user.sessions.create!(token: SecureRandom.hex(32))
    Dir.mktmpdir("waypoint-health-backup-test") do |directory|
      path = File.join(directory, "snapshot.sqlite3")
      counts = ServerBackup.call(path)
      run = BackupRun.order(:id).last
      assert_equal "succeeded", run.status
      assert run.available?
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal Digest::SHA256.file(path).hexdigest, run.sha256
      assert_operator counts["users"], :>=, 1
      snapshot = SQLite3::Database.new(path)
      assert_equal "ok", snapshot.get_first_value("PRAGMA integrity_check")
      assert_equal "180", JSON.parse(snapshot.get_first_value("SELECT weight_goal FROM users WHERE email_address = ?", [user.email_address]))["value"]
      snapshot.close
      assert_raises(Errno::EEXIST) { ServerBackup.call(path) }
      assert_equal "failed", BackupRun.order(:id).last.status
      assert_equal run.sha256, Digest::SHA256.file(path).hexdigest
      assert_raises(Errno::ENOENT) { ServerBackup.call(File.join(directory, "absent", "backup.sqlite3")) }
      restored = File.join(directory, "restored.sqlite3")
      output, error, status = Open3.capture3({ "RAILS_ENV" => "production", "DATABASE_PATH" => restored, "SECRET_KEY_BASE" => "test-only-restore-" * 8 }, Rails.root.join("bin/restore").to_s, path)
      assert status.success?, "Restore failed: #{output} #{error}"
      database = SQLite3::Database.new(restored)
      assert BCrypt::Password.new(database.get_first_value("SELECT password_digest FROM users WHERE email_address = ?", [user.email_address])) == "test-password-123"
      assert_equal 1, database.get_first_value("SELECT COUNT(*) FROM weights WHERE user_id = ?", [user.id])
      assert_equal 0, database.get_first_value("SELECT COUNT(*) FROM sessions")
      assert_equal 0, database.get_first_value("SELECT COUNT(*) FROM backup_runs")
      database.close
      File.delete(path)
      assert_not run.available?
    end
  ensure
    user&.destroy!
    BackupRun.delete_all
  end
end
