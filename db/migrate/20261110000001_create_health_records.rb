class CreateHealthRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :preferred_unit, null: false, default: "lb"
      t.string :time_zone, null: false, default: "America/New_York"
      t.json :enabled_metrics, null: false, default: []
      t.datetime :reminder_at
      t.timestamps
    end
    add_index :users, :email_address, unique: true
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
    add_index :sessions, :token, unique: true
    [:weights, :injections].each do |table|
      create_table table do |t|
        t.string :uuid, null: false
        t.references :user, null: false, foreign_key: true
        t.string :occurred_at, null: false
        t.datetime :recorded_at, null: false
        if table == :weights
          t.decimal :value, precision: 10, scale: 4, null: false
          t.string :unit, null: false
        else
          t.decimal :dose, precision: 5, scale: 2, null: false
          t.string :site
          t.string :side
          t.text :notes
        end
        t.timestamps
      end
      add_index table, [:user_id, :recorded_at]
      add_index table, [:user_id, :uuid], unique: true
    end
    create_table :day_notes do |t|
      t.string :uuid, null: false
      t.references :user, null: false, foreign_key: true
      t.date :local_date, null: false
      t.text :notes
      t.json :metrics, null: false, default: {}
      t.timestamps
    end
    add_index :day_notes, [:user_id, :local_date], unique: true
    add_index :day_notes, [:user_id, :uuid], unique: true
    create_table :import_batches, id: :string do |t|
      t.references :user, null: false, foreign_key: true
      t.json :payload, null: false
      t.datetime :committed_at
      t.timestamps
    end
    create_table :login_attempts do |t|
      t.string :key, null: false
      t.integer :count, null: false, default: 0
      t.datetime :window_started_at, null: false
    end
    add_index :login_attempts, :key, unique: true
  end
end
