class AddHeightToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :height_cm, :decimal, precision: 8, scale: 4
  end
end
