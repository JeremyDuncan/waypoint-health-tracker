class AddGoalsAndBackupRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :weight_goal, :json
    create_table :backup_runs do |t|
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.string :destination, null: false
      t.bigint :byte_size
      t.string :sha256
      t.timestamps
    end
    add_index :backup_runs, :started_at
  end
end
