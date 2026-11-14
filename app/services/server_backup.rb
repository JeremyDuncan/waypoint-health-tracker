require "sqlite3"
require "digest"

class ServerBackup
  def self.call(path)
    source_path = ActiveRecord::Base.connection_db_config.database
    raise ArgumentError, "Choose a destination different from the live database" if File.expand_path(path) == File.expand_path(source_path)
    run = BackupRun.create!(destination: File.expand_path(path), started_at: Time.current)
    source = target = backup = nil
    created = false
    begin
      # Exclusive creation prevents concurrent commands from overwriting a backup.
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { }
      created = true
      source = SQLite3::Database.new(source_path)
      source.busy_timeout = 10_000
      target = SQLite3::Database.new(path)
      backup = SQLite3::Backup.new(target, "main", source, "main")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
      loop do
        result = backup.step(128)
        break if result == SQLite3::Constants::ErrorCode::DONE
        unless [SQLite3::Constants::ErrorCode::OK, SQLite3::Constants::ErrorCode::BUSY, SQLite3::Constants::ErrorCode::LOCKED].include?(result)
          raise "SQLite backup failed: #{result}"
        end
        raise "Backup timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.02
      end
      backup.finish
      backup = nil
      target.execute("PRAGMA journal_mode=DELETE")
      raise "Backup integrity check failed" unless target.get_first_value("PRAGMA integrity_check") == "ok"
      counts = %w[users weights injections day_notes].to_h { |table| [table, target.get_first_value("SELECT COUNT(*) FROM #{table}")] }
      target.close
      target = nil
      run.update!(status: "succeeded", completed_at: Time.current, byte_size: File.size(path), sha256: Digest::SHA256.file(path).hexdigest)
      counts
    rescue StandardError
      run.update!(status: "failed", completed_at: Time.current)
      raise
    ensure
      backup&.finish
      target&.close
      source&.close
      File.delete(path) if created && run.status != "succeeded" && File.exist?(path)
    end
  end
end
