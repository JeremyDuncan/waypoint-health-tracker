class AddChartPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :chart_preferences, :json, default: {}, null: false
  end
end
